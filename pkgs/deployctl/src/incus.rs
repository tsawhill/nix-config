use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Error, Result};
use serde::Deserialize;

use crate::config::IncusGuestConfig;
use crate::process::{run_capture, run_logged};

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum InstanceState {
    Running,
    Stopped,
    Other(String),
}

impl InstanceState {
    fn from_status(status: String) -> Self {
        match status.as_str() {
            "Running" => Self::Running,
            "Stopped" => Self::Stopped,
            _ => Self::Other(status),
        }
    }
}

pub trait LifecycleBackend {
    fn state(&mut self) -> Result<InstanceState>;
    fn start(&mut self) -> Result<()>;
    fn wait_ready(&mut self) -> Result<()>;
    fn stop_and_verify(&mut self) -> Result<()>;
}

pub struct LifecycleOutcome<T> {
    pub operation: Result<T>,
    pub restoration_error: Option<Error>,
    pub started: bool,
}

/// Run one operation while preserving an intermittent guest's initial state.
///
/// Once a stopped guest has been started, restoration is attempted after both
/// readiness and operation failures. A guest that was already running is never
/// stopped by this controller.
pub fn with_lifecycle<T>(
    backend: &mut impl LifecycleBackend,
    operation: impl FnOnce() -> Result<T>,
) -> Result<LifecycleOutcome<T>> {
    match backend.state()? {
        InstanceState::Running => Ok(LifecycleOutcome {
            operation: operation(),
            restoration_error: None,
            started: false,
        }),
        InstanceState::Stopped => {
            backend.start()?;
            let operation = backend.wait_ready().and_then(|()| operation());
            let restoration_error = backend.stop_and_verify().err();
            Ok(LifecycleOutcome {
                operation,
                restoration_error,
                started: true,
            })
        }
        InstanceState::Other(state) => {
            bail!("refusing to change Incus instance in unexpected state {state:?}")
        }
    }
}

pub struct SshIncus {
    instance: String,
    manager: String,
    target: String,
    boot_timeout: Duration,
}

impl SshIncus {
    pub fn new(guest: &IncusGuestConfig, target: String, boot_timeout: Duration) -> Self {
        Self {
            instance: guest.instance.clone(),
            manager: guest.manager.clone(),
            target,
            boot_timeout,
        }
    }

    fn manager_command(&self) -> Command {
        let mut command = Command::new("ssh");
        command
            .args(["-o", "ConnectTimeout=15", "-o", "BatchMode=yes"])
            .arg(format!("root@{}", self.manager));
        command
    }

    fn query_state(&self) -> Result<InstanceState> {
        let path = format!("/1.0/instances/{}/state", self.instance);
        let output = run_capture(self.manager_command().args(["incus", "query"]).arg(path))?;
        if !output.success() {
            bail!(
                "failed to query Incus instance {} through {}:\n{}",
                self.instance,
                self.manager,
                output.text
            );
        }
        let response: StateResponse = serde_json::from_str(&output.stdout).with_context(|| {
            format!(
                "Incus returned invalid state JSON for {} through {}",
                self.instance, self.manager
            )
        })?;
        Ok(InstanceState::from_status(response.status))
    }
}

impl LifecycleBackend for SshIncus {
    fn state(&mut self) -> Result<InstanceState> {
        self.query_state()
    }

    fn start(&mut self) -> Result<()> {
        let output = run_logged(
            self.manager_command()
                .args(["incus", "start"])
                .arg(&self.instance),
        )?;
        if !output.success() {
            // The SSH/Incus command can report failure after the start request
            // has already taken effect. Treat a now-running instance as ours
            // so the lifecycle wrapper will still restore it afterward.
            if self.query_state()? == InstanceState::Running {
                return Ok(());
            }
            bail!(
                "failed to start Incus instance {} through {}:\n{}",
                self.instance,
                self.manager,
                output.text
            );
        }
        Ok(())
    }

    fn wait_ready(&mut self) -> Result<()> {
        let deadline = Instant::now() + self.boot_timeout;
        loop {
            let output = run_capture(
                Command::new("ssh")
                    .args(["-o", "ConnectTimeout=5", "-o", "BatchMode=yes"])
                    .arg(format!("root@{}", self.target))
                    .arg("true"),
            )?;
            if output.success() {
                return Ok(());
            }
            if Instant::now() >= deadline {
                bail!(
                    "Incus instance {} did not become reachable at {} within {} seconds:\n{}",
                    self.instance,
                    self.target,
                    self.boot_timeout.as_secs(),
                    output.tail(10)
                );
            }
            thread::sleep(Duration::from_secs(5));
        }
    }

    fn stop_and_verify(&mut self) -> Result<()> {
        let output = run_logged(
            self.manager_command()
                .args(["incus", "stop"])
                .arg(&self.instance)
                .args(["--timeout", "60"]),
        )?;
        let state = self.query_state()?;
        if state == InstanceState::Stopped {
            return Ok(());
        }
        if !output.success() {
            bail!(
                "failed to stop Incus instance {} gracefully through {}:\n{}",
                self.instance,
                self.manager,
                output.text
            );
        }
        bail!(
            "Incus stop completed but instance {} state is {:?}",
            self.instance,
            state
        )
    }
}

#[derive(Deserialize)]
struct StateResponse {
    status: String,
}

#[cfg(test)]
mod tests {
    use super::{with_lifecycle, InstanceState, LifecycleBackend};
    use anyhow::{bail, Result};

    struct FakeBackend {
        state: InstanceState,
        start_fails: bool,
        ready_fails: bool,
        stop_fails: bool,
        calls: Vec<&'static str>,
    }

    impl FakeBackend {
        fn new(state: InstanceState) -> Self {
            Self {
                state,
                start_fails: false,
                ready_fails: false,
                stop_fails: false,
                calls: Vec::new(),
            }
        }
    }

    impl LifecycleBackend for FakeBackend {
        fn state(&mut self) -> Result<InstanceState> {
            self.calls.push("state");
            Ok(self.state.clone())
        }

        fn start(&mut self) -> Result<()> {
            self.calls.push("start");
            if self.start_fails {
                bail!("start failed");
            }
            Ok(())
        }

        fn wait_ready(&mut self) -> Result<()> {
            self.calls.push("ready");
            if self.ready_fails {
                bail!("readiness failed");
            }
            Ok(())
        }

        fn stop_and_verify(&mut self) -> Result<()> {
            self.calls.push("stop");
            if self.stop_fails {
                bail!("stop failed");
            }
            Ok(())
        }
    }

    #[test]
    fn running_guest_is_left_running() {
        let mut backend = FakeBackend::new(InstanceState::Running);
        let outcome = with_lifecycle(&mut backend, || Ok("applied")).unwrap();
        assert_eq!(outcome.operation.unwrap(), "applied");
        assert!(!outcome.started);
        assert!(outcome.restoration_error.is_none());
        assert_eq!(backend.calls, ["state"]);
    }

    #[test]
    fn stopped_guest_is_started_and_restored() {
        let mut backend = FakeBackend::new(InstanceState::Stopped);
        let outcome = with_lifecycle(&mut backend, || Ok("applied")).unwrap();
        assert_eq!(outcome.operation.unwrap(), "applied");
        assert!(outcome.started);
        assert!(outcome.restoration_error.is_none());
        assert_eq!(backend.calls, ["state", "start", "ready", "stop"]);
    }

    #[test]
    fn unexpected_state_is_rejected_without_mutation() {
        let mut backend = FakeBackend::new(InstanceState::Other("Frozen".into()));
        let error = with_lifecycle(&mut backend, || Ok(())).err().unwrap();
        assert!(error.to_string().contains("unexpected state"));
        assert_eq!(backend.calls, ["state"]);
    }

    #[test]
    fn start_failure_does_not_claim_the_guest_needs_restoration() {
        let mut backend = FakeBackend::new(InstanceState::Stopped);
        backend.start_fails = true;
        let error = with_lifecycle(&mut backend, || Ok(())).err().unwrap();
        assert!(error.to_string().contains("start failed"));
        assert_eq!(backend.calls, ["state", "start"]);
    }

    #[test]
    fn readiness_failure_still_restores_the_guest() {
        let mut backend = FakeBackend::new(InstanceState::Stopped);
        backend.ready_fails = true;
        let outcome = with_lifecycle(&mut backend, || Ok(())).unwrap();
        assert!(outcome.operation.is_err());
        assert!(outcome.restoration_error.is_none());
        assert_eq!(backend.calls, ["state", "start", "ready", "stop"]);
    }

    #[test]
    fn operation_failure_still_restores_the_guest() {
        let mut backend = FakeBackend::new(InstanceState::Stopped);
        let outcome: super::LifecycleOutcome<()> =
            with_lifecycle(&mut backend, || bail!("apply failed")).unwrap();
        assert!(outcome.operation.is_err());
        assert!(outcome.restoration_error.is_none());
        assert_eq!(backend.calls, ["state", "start", "ready", "stop"]);
    }

    #[test]
    fn successful_operation_reports_restoration_failure() {
        let mut backend = FakeBackend::new(InstanceState::Stopped);
        backend.stop_fails = true;
        let outcome = with_lifecycle(&mut backend, || Ok("applied")).unwrap();
        assert_eq!(outcome.operation.unwrap(), "applied");
        assert!(outcome.restoration_error.is_some());
        assert_eq!(backend.calls, ["state", "start", "ready", "stop"]);
    }
}

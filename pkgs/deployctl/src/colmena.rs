use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use chrono::Utc;

use crate::cli::DeployGoal;
use crate::config::Config;
use crate::hosts::ssh_host;
use crate::process::{phase, run_capture, run_logged, RunOutput};
use crate::retry::sanitize_label;

const LOCAL_NIXOS_VERSION: &str = "/run/current-system/sw/bin/nixos-version";

pub struct BuildResult {
    pub output: Arc<RunOutput>,
    pub system_path: Option<PathBuf>,
    // Nix's result links are GC roots. Keep the batch alive until every host
    // has been pinned/applied, even if an earlier host takes hours to activate.
    _roots: Arc<BuildRoots>,
}

struct BuildRoots {
    dir: PathBuf,
}

impl BuildRoots {
    fn new() -> Result<Self> {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        loop {
            let dir = std::env::temp_dir().join(format!(
                "deployctl-build-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            match fs::create_dir(&dir) {
                Ok(()) => return Ok(Self { dir }),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error).context("creating temporary build roots"),
            }
        }
    }
}

impl Drop for BuildRoots {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

struct BuildAttempt {
    output: Arc<RunOutput>,
    roots: Arc<BuildRoots>,
}

impl BuildAttempt {
    fn result(&self, index: usize) -> BuildResult {
        let system_path = if self.output.success() {
            match result_path(&self.roots.dir, index) {
                Ok(path) => Some(path),
                Err(error) => {
                    eprintln!("warning: invalid build result: {error:#}");
                    None
                }
            }
        } else {
            None
        };
        BuildResult {
            output: self.output.clone(),
            system_path,
            _roots: self.roots.clone(),
        }
    }
}

/// Result links are indexed by the installable's command-line position, not
/// build completion order. Never infer a host's result from mixed build logs.
fn result_path(dir: &Path, index: usize) -> Result<PathBuf> {
    let name = if index == 0 {
        "result".to_owned()
    } else {
        format!("result-{index}")
    };
    let path = fs::read_link(dir.join(name)).context("reading Nix result link")?;
    anyhow::ensure!(
        path.parent() == Some(Path::new("/nix/store"))
            && path
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.contains("-nixos-system-") && !name.ends_with(".drv")),
        "expected a NixOS system output, got {}",
        path.display()
    );
    Ok(path)
}

/// Failed grouped evaluation must not prevent a healthy sibling deploying.
/// Nix may have built some outputs before failing; individual retries reuse
/// those store objects but obtain fresh, unambiguous result roots.
fn build_batch_with(
    hosts: &[String],
    mut run: impl FnMut(&[String]) -> Result<BuildAttempt>,
) -> Result<BTreeMap<String, BuildResult>> {
    if hosts.is_empty() {
        return Ok(BTreeMap::new());
    }
    let attempt = run(hosts)?;
    let results: BTreeMap<_, _> = hosts
        .iter()
        .enumerate()
        .map(|(index, host)| (host.clone(), attempt.result(index)))
        .collect();
    if hosts.len() == 1 || results.values().all(|result| result.system_path.is_some()) {
        return Ok(results);
    }
    phase("Batch did not complete; retrying hosts individually to isolate failures");
    let mut individual = BTreeMap::new();
    for host in hosts {
        let attempt = run(std::slice::from_ref(host))?;
        individual.insert(host.clone(), attempt.result(0));
    }
    Ok(individual)
}

#[derive(Clone)]
pub struct Colmena {
    config: Config,
}

impl Colmena {
    pub fn new(config: Config) -> Self {
        Self { config }
    }

    pub fn build_batch(
        &self,
        flake_uri: &str,
        hosts: &[String],
    ) -> Result<BTreeMap<String, BuildResult>> {
        build_batch_with(hosts, |hosts| {
            let duration = if hosts.len() == 1 {
                &self.config.per_host_build_timeout
            } else {
                &self.config.batch_build_timeout
            };
            phase(format!(
                "Pure build started: {} (timeout {duration})",
                hosts.join(", ")
            ));
            let started = Instant::now();
            let roots = Arc::new(BuildRoots::new()?);
            let mut command = timeout_command(duration);
            command
                .args([
                    "nix",
                    "build",
                    "--no-update-lock-file",
                    "--keep-going",
                    "--print-build-logs",
                ])
                .args(["--option", "pure-eval", "true"])
                .arg("--out-link")
                .arg(roots.dir.join("result"))
                .args(
                    hosts
                        .iter()
                        .map(|host| format!("{flake_uri}#colmenaHive.toplevel.\"{host}\"")),
                )
                .current_dir(&self.config.repo_path);
            let output = Arc::new(run_logged(&mut command)?);
            phase(format!(
                "Pure build finished: {} ({}s, exit {})",
                hosts.join(", "),
                started.elapsed().as_secs(),
                output.code()
            ));
            Ok(BuildAttempt { output, roots })
        })
    }

    pub fn apply(&self, host: &str, system_path: &Path, goal: DeployGoal) -> Result<RunOutput> {
        let self_hostname = hostname()?;
        if host == self_hostname || (host == "build-nix" && self_hostname == "build-nix") {
            self.apply_local(system_path, goal)
        } else {
            self.apply_remote(host, system_path, goal)
        }
    }

    fn apply_local(&self, system_path: &Path, goal: DeployGoal) -> Result<RunOutput> {
        let profile = self.config.system_profile.to_string_lossy().into_owned();
        let set = run_logged(
            Command::new("nix-env")
                .args(["-p", &profile, "--set"])
                .arg(system_path),
        )?;
        if !set.success() {
            return Ok(set);
        }

        let mut command = timeout_command(&self.config.apply_timeout);
        command
            .arg(system_path.join("bin/switch-to-configuration"))
            .arg(goal.as_str());
        combine(set, run_logged(&mut command)?)
    }

    fn apply_remote(&self, host: &str, system_path: &Path, goal: DeployGoal) -> Result<RunOutput> {
        let target = ssh_host(&self.config, host);
        let ssh_options = "-o ConnectTimeout=15 -o BatchMode=yes";
        let mut copy_command = timeout_command(&self.config.apply_timeout);
        copy_command
            .args(["nix", "copy", "--to", &format!("ssh://root@{target}")])
            .arg(system_path)
            .env("NIX_SSHOPTS", ssh_options);
        let copy = run_logged(&mut copy_command)?;
        if !copy.success() {
            return Ok(copy);
        }

        // Both interpolated values are constrained: Nix store paths cannot
        // contain shell metacharacters and DeployGoal is an enum.
        let remote = format!(
            "nix-env -p /nix/var/nix/profiles/system --set {0} && {0}/bin/switch-to-configuration {1}",
            system_path.display(),
            goal.as_str()
        );
        let mut activate_command = timeout_command(&self.config.apply_timeout);
        activate_command
            .args(["ssh", "-o", "ConnectTimeout=15", "-o", "BatchMode=yes"])
            .arg(format!("root@{target}"))
            .arg(remote);
        combine(copy, run_logged(&mut activate_command)?)
    }

    pub fn try_wol(&self, host: &str) {
        let Some(mac) = self.config.wol_macs.get(host) else {
            return;
        };
        println!("Sending Wake-on-LAN to {host} ({mac})...");
        let _ = Command::new("wol").arg(mac).status();
        thread::sleep(Duration::from_secs(60));
    }

    /// The closure a host is running now, for comparison against the new build.
    ///
    /// The host's own profile is the truth, but `nix store diff-closures` needs
    /// both closures present locally, so an unknown remote path falls back to
    /// the newest pin this controller took for that host. Call this before
    /// pinning the new build, or the newest pin *is* the new build.
    pub fn previous_system(&self, host: &str) -> Option<PathBuf> {
        self.deployed_system(host)
            .filter(|path| path.exists())
            .or_else(|| self.latest_pin(host))
    }

    fn deployed_system(&self, host: &str) -> Option<PathBuf> {
        let profile = self.config.system_profile.to_string_lossy().into_owned();
        let output = if host == hostname().ok()? {
            run_capture(Command::new("readlink").arg("-f").arg(&profile))
        } else {
            let target = ssh_host(&self.config, host);
            run_capture(
                Command::new("ssh")
                    .args(["-o", "ConnectTimeout=5", "-o", "BatchMode=yes"])
                    .arg(format!("root@{target}"))
                    .arg(format!("readlink -f {profile}")),
            )
        };
        let path = output
            .ok()
            .filter(RunOutput::success)?
            .stdout
            .trim()
            .to_owned();
        if path.starts_with("/nix/store/") {
            Some(PathBuf::from(path))
        } else {
            None
        }
    }

    fn latest_pin(&self, host: &str) -> Option<PathBuf> {
        self.recent_pins(host, 1).into_iter().next()
    }

    /// The most recently pinned closures for a host, newest first.
    ///
    /// Rebuilding an unchanged host pins the same store path again, so repeats
    /// are collapsed: two identical entries would diff to nothing.
    pub fn recent_pins(&self, host: &str, count: usize) -> Vec<PathBuf> {
        let Ok(entries) = fs::read_dir(self.config.built_gcroot_dir.join(host)) else {
            return Vec::new();
        };
        let mut roots: Vec<_> = entries
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .collect();
        // Root names begin with a sortable timestamp.
        roots.sort();

        let mut pins: Vec<PathBuf> = Vec::with_capacity(count);
        for root in roots.iter().rev() {
            let Ok(path) = fs::canonicalize(root) else {
                continue;
            };
            if pins.contains(&path) {
                continue;
            }
            pins.push(path);
            if pins.len() == count {
                break;
            }
        }
        pins
    }

    pub fn pin_built_system(&self, host: &str, system_path: &Path) -> Result<()> {
        if !system_path.exists() {
            bail!("cannot pin missing system path {}", system_path.display());
        }
        println!("Pinning built system for {host}: {}", system_path.display());
        let host_dir = self.config.built_gcroot_dir.join(host);
        fs::create_dir_all(&host_dir)?;
        let timestamp = Utc::now().format("%Y%m%d%H%M%S");
        let basename = system_path
            .file_name()
            .and_then(|name| name.to_str())
            .context("system path has no UTF-8 basename")?;
        let root = host_dir.join(format!("{timestamp}-built-{}", sanitize_label(basename)));
        let output = run_capture(
            Command::new("nix-store")
                .args(["--add-root"])
                .arg(&root)
                .args(["--indirect", "--realise"])
                .arg(system_path),
        )?;
        if !output.success() {
            bail!("failed to pin {}:\n{}", system_path.display(), output.text);
        }
        let keep_roots = if self.config.incus_guests.contains_key(host) {
            self.config.incus_keep_roots
        } else {
            self.config.keep_roots
        };
        self.prune_host_roots(&host_dir, keep_roots)?;
        Ok(())
    }

    fn prune_host_roots(&self, host_dir: &Path, keep_roots: usize) -> Result<()> {
        let mut roots: Vec<_> = fs::read_dir(host_dir)?
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .collect();
        roots.sort_by(|left, right| right.file_name().cmp(&left.file_name()));
        for root in roots.into_iter().skip(keep_roots) {
            let _ = fs::remove_file(root);
        }
        Ok(())
    }

    pub fn prune_removed_hosts(&self, known: &BTreeSet<String>) -> Result<()> {
        if !self.config.built_gcroot_dir.exists() {
            return Ok(());
        }
        for entry in fs::read_dir(&self.config.built_gcroot_dir)? {
            let entry = entry?;
            if !entry.file_type()?.is_dir() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            if !known.contains(&name) {
                fs::remove_dir_all(entry.path())?;
            }
        }
        Ok(())
    }

    pub fn version(&self, host: &str) -> String {
        let Ok(self_hostname) = hostname() else {
            return "unknown".to_owned();
        };
        let output = if host == self_hostname {
            // The deploy service's PATH has no /run/current-system/sw/bin.
            run_capture(&mut Command::new(LOCAL_NIXOS_VERSION))
        } else {
            let target = ssh_host(&self.config, host);
            run_capture(
                Command::new("ssh")
                    .args(["-o", "ConnectTimeout=5", "-o", "BatchMode=yes"])
                    .arg(format!("root@{target}"))
                    .arg("nixos-version"),
            )
        };
        output
            .ok()
            .filter(RunOutput::success)
            .map(|output| output.stdout.trim().to_owned())
            .filter(|version| !version.is_empty())
            .unwrap_or_else(|| "unreachable".to_owned())
    }
}

pub fn is_retryable(output: &RunOutput) -> bool {
    if matches!(output.code(), 124 | 137) {
        return true;
    }
    let text = output.text.to_ascii_lowercase();
    [
        "ssh: connect",
        "connection refused",
        "no route to host",
        "connection timed out",
        "network is unreachable",
        "could not connect",
        "could not resolve hostname",
        "ssh_exchange_identification",
        "kex_exchange_identification",
        "connection reset",
        "connection closed",
        "broken pipe",
        "host is down",
        "operation timed out",
        "failed to connect",
        "cannot connect",
    ]
    .iter()
    .any(|marker| text.contains(marker))
}

fn timeout_command(duration: &str) -> Command {
    let mut command = Command::new("timeout");
    command.args(["--foreground", "--kill-after=60s", duration]);
    command
}

fn hostname() -> Result<String> {
    let output = run_capture(&mut Command::new("hostname"))?;
    if !output.success() {
        bail!("hostname failed: {}", output.text);
    }
    Ok(output.stdout.trim().to_owned())
}

fn combine(first: RunOutput, second: RunOutput) -> Result<RunOutput> {
    let mut text = first.text;
    text.push_str(&second.text);
    Ok(RunOutput {
        status: second.status,
        stdout: second.stdout,
        text,
    })
}

#[cfg(test)]
mod tests {
    use super::{build_batch_with, result_path, BuildAttempt, BuildRoots};
    use crate::process::RunOutput;
    use std::fs;
    use std::os::unix::{fs::symlink, process::ExitStatusExt};
    use std::path::PathBuf;
    use std::process::ExitStatus;
    use std::sync::Arc;

    fn attempt(hosts: &[String], success: bool) -> BuildAttempt {
        let roots = Arc::new(BuildRoots::new().unwrap());
        if success {
            for (index, host) in hosts.iter().enumerate() {
                let name = if index == 0 {
                    "result".to_owned()
                } else {
                    format!("result-{index}")
                };
                symlink(
                    format!("/nix/store/aaaaaaaa-nixos-system-{host}-1"),
                    roots.dir.join(name),
                )
                .unwrap();
            }
        }
        BuildAttempt {
            roots,
            output: Arc::new(RunOutput {
                status: ExitStatus::from_raw(if success { 0 } else { 256 }),
                stdout: String::new(),
                // Neither another host's path nor a .drv in logs is a result.
                text: "noise /nix/store/bbbbbbbb-nixos-system-wrong-1.drv".to_owned(),
            }),
        }
    }

    #[test]
    fn successful_batch_builds_once_and_maps_each_result() {
        let hosts = vec!["one".to_owned(), "two".to_owned()];
        let mut calls = Vec::new();
        let mut results = build_batch_with(&hosts, |selected| {
            calls.push(selected.to_vec());
            Ok(attempt(selected, true))
        })
        .unwrap();
        assert_eq!(calls, vec![hosts]);
        assert_eq!(
            results["one"].system_path,
            Some(PathBuf::from("/nix/store/aaaaaaaa-nixos-system-one-1"))
        );
        assert_eq!(
            results["two"].system_path,
            Some(PathBuf::from("/nix/store/aaaaaaaa-nixos-system-two-1"))
        );

        let root_dir = results["one"]._roots.dir.clone();
        drop(results.remove("one"));
        assert!(
            root_dir.exists(),
            "remaining host must stay rooted during activation"
        );
        drop(results);
        assert!(!root_dir.exists(), "completed batch must not leak GC roots");
    }

    #[test]
    fn failed_batch_isolates_a_bad_host_and_preserves_healthy_hosts() {
        let hosts = vec!["good".to_owned(), "bad".to_owned(), "another".to_owned()];
        let mut calls = Vec::new();
        let results = build_batch_with(&hosts, |selected| {
            calls.push(selected.to_vec());
            Ok(attempt(
                selected,
                selected.len() == 1 && selected[0] != "bad",
            ))
        })
        .unwrap();
        assert_eq!(
            calls,
            vec![
                hosts,
                vec!["good".into()],
                vec!["bad".into()],
                vec!["another".into()]
            ]
        );
        assert!(results["good"].system_path.is_some());
        assert!(results["bad"].system_path.is_none());
        assert!(!results["bad"].output.success());
        assert!(results["another"].system_path.is_some());
    }

    #[test]
    fn incomplete_successful_batch_retries_instead_of_misassigning_a_host() {
        let hosts = vec!["one".to_owned(), "two".to_owned()];
        let mut calls = 0;
        let results = build_batch_with(&hosts, |selected| {
            calls += 1;
            let result = attempt(selected, true);
            if selected.len() > 1 {
                fs::remove_file(result.roots.dir.join("result-1")).unwrap();
            }
            Ok(result)
        })
        .unwrap();
        assert_eq!(calls, 3);
        assert!(results.values().all(|result| result.system_path.is_some()));
    }

    #[test]
    fn failed_single_host_is_not_retried_forever() {
        let mut calls = 0;
        let results = build_batch_with(&["bad".into()], |selected| {
            calls += 1;
            Ok(attempt(selected, false))
        })
        .unwrap();
        assert_eq!(calls, 1);
        assert!(results["bad"].system_path.is_none());
    }

    #[test]
    fn result_links_must_point_to_a_system_output() {
        let roots = BuildRoots::new().unwrap();
        for invalid in [
            "/tmp/aaaaaaaa-nixos-system-one",
            "/nix/store/aaa-nixos-system-one.drv",
            "/nix/store/aaa-bash",
            "/nix/store/aaa-nixos-system-one/bin",
        ] {
            let link = roots.dir.join("result");
            symlink(invalid, &link).unwrap();
            assert!(result_path(&roots.dir, 0).is_err());
            fs::remove_file(link).unwrap();
        }
    }
}

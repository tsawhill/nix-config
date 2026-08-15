use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

use anyhow::{bail, Context, Result};
use chrono::Utc;

use crate::cli::DeployGoal;
use crate::config::Config;
use crate::hosts::{list_all, ssh_host};
use crate::process::{phase, run_capture, run_logged, RunOutput};
use crate::retry::sanitize_label;

pub struct BuildResult {
    pub output: RunOutput,
    pub system_path: Option<PathBuf>,
}

#[derive(Clone)]
pub struct Colmena {
    config: Config,
}

impl Colmena {
    pub fn new(config: Config) -> Self {
        Self { config }
    }

    pub fn build(&self, host: &str) -> Result<BuildResult> {
        phase(format!(
            "{host}: per-host build started (timeout {})",
            self.config.per_host_build_timeout
        ));
        let mut command = timeout_command(&self.config.per_host_build_timeout);
        command
            .args(["colmena", "build", "--on", host])
            .args(["--no-build-on-target", "--parallel", "1"])
            .current_dir(&self.config.repo_path);
        let output = run_logged(&mut command)?;
        let system_path = if output.success() {
            discover_system_path(&output.text)
        } else {
            None
        };
        if let Some(path) = &system_path {
            phase(format!(
                "{host}: per-host build completed ({})",
                path.display()
            ));
        }
        Ok(BuildResult {
            output,
            system_path,
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
        let root = host_dir.join(format!(
            "{timestamp}-built-{}",
            sanitize_label(basename)
        ));
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
        self.prune_host_roots(&host_dir)?;
        self.prune_removed_hosts()?;
        Ok(())
    }

    fn prune_host_roots(&self, host_dir: &Path) -> Result<()> {
        let mut roots: Vec<_> = fs::read_dir(host_dir)?
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .collect();
        roots.sort_by(|left, right| right.file_name().cmp(&left.file_name()));
        for root in roots.into_iter().skip(self.config.keep_roots) {
            let _ = fs::remove_file(root);
        }
        Ok(())
    }

    fn prune_removed_hosts(&self) -> Result<()> {
        let known: BTreeSet<_> = list_all(&self.config)?.into_iter().collect();
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
            run_capture(&mut Command::new("nixos-version"))
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

fn discover_system_path(text: &str) -> Option<PathBuf> {
    text.split_whitespace()
        .filter_map(|token| {
            let token = token.trim_matches(|character: char| {
                matches!(character, '"' | '\'' | '(' | ')' | '[' | ']' | ',' | ':')
            });
            (token.starts_with("/nix/store/") && token.contains("-nixos-system-"))
                .then(|| PathBuf::from(token))
        })
        .last()
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
    use super::discover_system_path;
    use std::path::PathBuf;

    #[test]
    fn finds_the_last_built_system_path() {
        let log = r#"noise
          /nix/store/aaaaaaaa-nixos-system-one-1
          Built "/nix/store/bbbbbbbb-nixos-system-two-2"
        "#;
        assert_eq!(
            discover_system_path(log),
            Some(PathBuf::from(
                "/nix/store/bbbbbbbb-nixos-system-two-2"
            ))
        );
    }
}

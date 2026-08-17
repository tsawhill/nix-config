use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use std::process::Command;

use anyhow::{bail, Context, Result};
use chrono::{Local, Utc};

use crate::changes::{closure_packages, DeployChanges, HostChange};
use crate::cli::DeployGoal;
use crate::colmena::{is_retryable, BuildResult, Colmena};
use crate::config::Config;
use crate::hosts::{controller_last, expand_selector, list_all, ssh_host};
use crate::locking::{DeployLock, LockMode};
use crate::notifications::{deploy_log_email_body, has_warnings, Notifier};
use crate::process::{phase, run_capture, run_logged, RunOutput};
use crate::retry::RetryStore;
use crate::summarize::Summarizer;

pub struct Controller {
    config: Config,
    colmena: Colmena,
    retries: RetryStore,
    notifier: Notifier,
    summarizer: Summarizer,
}

impl Controller {
    pub fn new(config: Config) -> Self {
        Self {
            colmena: Colmena::new(config.clone()),
            retries: RetryStore::new(
                config.retry_state_dir.clone(),
                config.retry_gcroot_dir.clone(),
            ),
            notifier: Notifier::new(config.notifications.clone()),
            summarizer: Summarizer::new(config.summary.clone()),
            config,
        }
    }

    pub fn plan(&self, selector: &str, ordered: bool) -> Result<()> {
        let mut hosts = expand_selector(&self.config, selector)?;
        if ordered {
            hosts = controller_last(hosts);
        }
        if hosts.is_empty() {
            bail!(
                "no hosts matched selector {selector:?}; known hosts: {}",
                list_all(&self.config)?.join(" ")
            );
        }
        for (index, host) in hosts.iter().enumerate() {
            println!("{:>2}. {host}", index + 1);
        }
        Ok(())
    }

    pub fn deploy_manual(&self, selector: &str, goal: DeployGoal) -> Result<()> {
        let Some(_lock) = DeployLock::acquire(
            &self.config.deploy_lock_path,
            "manual deploy",
            LockMode::Prompt,
        )? else {
            bail!("manual deploy did not wait for the deploy lock");
        };

        // Read the marker before the pre-deploy commit so a first run still
        // sees the working-tree edits it is about to deploy.
        let base = self.summary_base();
        self.pre_deploy_commit(&format!("manual deploy {selector}"))?;
        phase(format!("Manual deploy {selector}: resolving hosts"));
        let hosts = controller_last(expand_selector(&self.config, selector)?);
        if hosts.is_empty() {
            bail!(
                "no hosts matched selector {selector:?}; known hosts: {}",
                list_all(&self.config)?.join(" ")
            );
        }
        phase(format!(
            "Manual deploy {selector}: hosts to deploy: {}",
            hosts.join(" ")
        ));

        let mut succeeded = BTreeSet::new();
        let mut failed = BTreeSet::new();
        let mut deployed = Vec::new();
        let mut had_warnings = false;

        for host in hosts {
            phase(format!(
                "{host}: manual build phase ({})",
                goal.as_str()
            ));
            let build = self.colmena.build(&host)?;
            let Some(system_path) = self.accept_build(&host, &build, "Manual deploy") else {
                failed.insert(host);
                continue;
            };
            let previous = self.colmena.previous_system(&host);
            if let Err(error) = self.colmena.pin_built_system(&host, &system_path) {
                eprintln!("warning: failed to pin {host}: {error:#}");
            }

            phase(format!(
                "{host}: manual exact-path apply started ({}, timeout {})",
                goal.as_str(),
                self.config.apply_timeout
            ));
            let output = self.colmena.apply(&host, &system_path, goal)?;
            had_warnings |= has_warnings(&output);
            if output.success() {
                phase(format!("{host}: manual exact-path apply completed"));
                succeeded.insert(host.clone());
                deployed.push(self.host_change(&host, previous.as_deref(), &system_path));
                self.retries.clear_host(&host)?;
            } else {
                failed.insert(host.clone());
                self.notify_host_failure(
                    &format!("❌ Manual deploy {host} FAILED"),
                    &output,
                    &format!("Build log excerpt for manual deploy {host} (goal={}).", goal.as_str()),
                );
            }
        }

        phase(format!(
            "Manual deploy {selector}: final summary; succeeded={} failed={} goal={}",
            display_set(&succeeded),
            display_set(&failed),
            goal.as_str()
        ));
        let report = self.record_deploy(selector, base.as_deref(), deployed);
        if failed.is_empty() {
            let title = if had_warnings {
                format!("⚠️ Manual deploy {selector} succeeded (with warnings)")
            } else {
                format!("✅ Manual deploy {selector} succeeded")
            };
            self.notifier.notify(
                &title,
                if had_warnings { 4 } else { 3 },
                &with_report(
                    &format!(
                        "Succeeded: {}\nGoal: {}",
                        display_set(&succeeded),
                        goal.as_str()
                    ),
                    report.as_deref(),
                ),
            );
            Ok(())
        } else {
            self.notifier.notify(
                &format!("⚠️ Manual deploy {selector} partial"),
                6,
                &with_report(
                    &format!(
                        "Succeeded: {}\nFailed: {}\nGoal: {}",
                        display_set(&succeeded),
                        display_set(&failed),
                        goal.as_str()
                    ),
                    report.as_deref(),
                ),
            );
            bail!("one or more manual deployments failed")
        }
    }

    pub fn deploy_scheduled(&self, schedule: &str, selector: &str) -> Result<()> {
        let _lock = DeployLock::acquire(
            &self.config.deploy_lock_path,
            &format!("{schedule} deploy"),
            LockMode::Wait,
        )?
        .context("blocking deploy lock unexpectedly returned no guard")?;

        let base = self.summary_base();
        self.pre_deploy_commit(&format!("{schedule} pre-deploy"))?;
        phase(format!("Deploying {schedule} ({selector})"));
        let hosts = controller_last(expand_selector(&self.config, selector)?);
        if hosts.is_empty() {
            phase(format!("No hosts found for selector {selector:?}"));
            return Ok(());
        }
        phase(format!(
            "{schedule}: hosts to deploy: {}",
            hosts.join(" ")
        ));
        self.retries.clear_schedule(schedule)?;
        let build_id = Utc::now().format("%Y%m%d%H%M%S").to_string();

        let mut succeeded = BTreeSet::new();
        let mut hard_failed = BTreeSet::new();
        let mut deferred = BTreeSet::new();
        let mut deployed = Vec::new();
        let mut had_warnings = false;

        for host in hosts {
            phase(format!("{host}: scheduled build phase"));
            let build = self.colmena.build(&host)?;
            let Some(system_path) = self.accept_build(&host, &build, schedule) else {
                hard_failed.insert(host);
                continue;
            };
            let previous = self.colmena.previous_system(&host);
            if let Err(error) = self.colmena.pin_built_system(&host, &system_path) {
                eprintln!("warning: failed to pin {host}: {error:#}");
            }

            self.retries.clear_host(&host)?;
            phase(format!("{host}: queueing retry record for {}", system_path.display()));
            let record = self.retries.new_record(
                schedule,
                selector,
                &host,
                system_path.clone(),
                DeployGoal::Switch,
                &build_id,
            );
            self.retries.write(&record)?;

            phase(format!(
                "{host}: first exact-path apply started (timeout {})",
                self.config.apply_timeout
            ));
            let output = self
                .colmena
                .apply(&host, &system_path, DeployGoal::Switch)?;
            had_warnings |= has_warnings(&output);
            if output.success() {
                phase(format!("{host}: first exact-path apply completed"));
                succeeded.insert(host.clone());
                deployed.push(self.host_change(&host, previous.as_deref(), &system_path));
                self.retries.delete(schedule, &host)?;
            } else if is_retryable(&output) {
                deferred.insert(host.clone());
                self.notifier.notify(
                    &format!("⚠️ {schedule}: {host} deferred"),
                    5,
                    &format!(
                        "First apply failed or timed out; retrying every 30 minutes until the next {schedule} build.\nSystem: {}\nLast 20 lines:\n{}",
                        system_path.display(),
                        output.tail(20)
                    ),
                );
            } else {
                hard_failed.insert(host.clone());
                self.retries.delete(schedule, &host)?;
                self.notify_host_failure(
                    &format!("❌ {schedule}: {host} FAILED"),
                    &output,
                    &format!("Build log excerpt for {host} ({schedule})."),
                );
            }
        }

        self.notifier.notify(
            &format!("ℹ️ {schedule} first-pass summary"),
            3,
            &format!(
                "Succeeded: {}\nHard failed: {}\nDeferred: {}",
                display_set(&succeeded),
                display_set(&hard_failed),
                display_set(&deferred)
            ),
        );

        phase(format!(
            "{schedule}: final summary; succeeded={} hard_failed={} deferred={}",
            display_set(&succeeded),
            display_set(&hard_failed),
            display_set(&deferred)
        ));
        let report = self.record_deploy(schedule, base.as_deref(), deployed);
        let (title, priority, body) = if !hard_failed.is_empty() {
            (
                format!("⚠️ {schedule} deploy partial"),
                6,
                format!(
                    "Succeeded: {}\nFailed: {}\nDeferred: {}",
                    display_set(&succeeded),
                    display_set(&hard_failed),
                    display_set(&deferred)
                ),
            )
        } else if !deferred.is_empty() {
            (
                format!("⚠️ {schedule} deploy deferred"),
                5,
                format!(
                    "Succeeded: {}\nDeferred: {}",
                    display_set(&succeeded),
                    display_set(&deferred)
                ),
            )
        } else if had_warnings {
            (
                format!("⚠️ {schedule} deploy succeeded (with warnings)"),
                4,
                format!("All hosts: {}", display_set(&succeeded)),
            )
        } else {
            (
                format!("✅ {schedule} deploy succeeded"),
                3,
                format!("All hosts: {}", display_set(&succeeded)),
            )
        };
        self.notifier
            .notify(&title, priority, &with_report(&body, report.as_deref()));
        if hard_failed.is_empty() {
            Ok(())
        } else {
            bail!("one or more scheduled deployments failed")
        }
    }

    pub fn retry_deferred(&self) -> Result<()> {
        let Some(_lock) = DeployLock::acquire(
            &self.config.deploy_lock_path,
            "deploy retry",
            LockMode::Skip,
        )? else {
            return Ok(());
        };

        fs::create_dir_all(&self.config.retry_state_dir)?;
        phase(format!(
            "Deploy retry: scanning {}",
            self.config.retry_state_dir.display()
        ));
        for path in self.retries.paths()? {
            let record = match self.retries.load(&path) {
                Ok(record) => record,
                Err(error) => {
                    phase(format!(
                        "Deploy retry: removing invalid retry record {}: {error:#}",
                        path.display()
                    ));
                    fs::remove_file(path)?;
                    continue;
                }
            };
            if !record.system_path.exists() {
                self.notifier.notify_email(
                    &format!("❌ Deploy retry {} stale", record.host),
                    10,
                    &format!(
                        "Queued retry cannot continue because the local system path is missing:\n{}",
                        record.system_path.display()
                    ),
                    &format!(
                        "Queued retry cannot continue because the local system path is missing:\n{}",
                        record.system_path.display()
                    ),
                );
                self.retries.delete(&record.schedule, &record.host)?;
                continue;
            }

            phase(format!(
                "Deploy retry: {} from {} build {} exact-path apply started (timeout {})",
                record.host, record.schedule, record.build_id, self.config.apply_timeout
            ));
            self.colmena.try_wol(&record.host);
            let output = self
                .colmena
                .apply(&record.host, &record.system_path, record.goal)?;
            if output.success() {
                phase(format!("Deploy retry: {} succeeded", record.host));
                self.retries.delete(&record.schedule, &record.host)?;
                self.notifier.notify(
                    &format!("✅ Deploy retry {} succeeded", record.host),
                    3,
                    &format!(
                        "{} applied queued {} build {}.\nSystem: {}",
                        record.host,
                        record.schedule,
                        record.build_id,
                        record.system_path.display()
                    ),
                );
            } else if is_retryable(&output) {
                phase(format!(
                    "Deploy retry: {} still unreachable or timed out; keeping queued retry",
                    record.host
                ));
            } else {
                phase(format!(
                    "Deploy retry: {} failed hard; removing queued retry",
                    record.host
                ));
                self.retries.delete(&record.schedule, &record.host)?;
                self.notify_host_failure(
                    &format!("❌ Deploy retry {} FAILED", record.host),
                    &output,
                    &format!(
                        "Retry log excerpt for {} ({} build {}).",
                        record.host, record.schedule, record.build_id
                    ),
                );
            }
        }
        Ok(())
    }

    /// Summarise the newest pinned build against the one before it.
    ///
    /// Read-only: it takes no lock, commits nothing, and moves no ref, so the
    /// model and the prompt can be exercised against real closures at any time.
    pub fn summarize_last(&self, selector: &str, show_prompt: bool) -> Result<()> {
        let hosts = expand_selector(&self.config, selector)?;
        if hosts.is_empty() {
            bail!(
                "no hosts matched selector {selector:?}; known hosts: {}",
                list_all(&self.config)?.join(" ")
            );
        }

        let mut deployed = Vec::new();
        for host in hosts {
            match self.colmena.recent_pins(&host, 2).as_slice() {
                [current, previous] => {
                    deployed.push(self.host_change(&host, Some(previous.as_path()), current));
                }
                [current] => deployed.push(self.host_change(&host, None, current)),
                _ => eprintln!("warning: no pinned builds for {host}; skipping"),
            }
        }
        if deployed.is_empty() {
            bail!("no pinned builds found for selector {selector:?}");
        }

        let versions: Vec<String> = deployed
            .iter()
            .map(|host| format!("{}: {}", host.host, host.version))
            .collect();
        let base = self.summary_base();
        let changes = DeployChanges::collect(&self.config, selector, base.as_deref(), deployed);
        if show_prompt {
            println!("--- prompt ---\n{}\n--- reply ---", changes.prompt());
        }
        let summary = self.summarizer.summarize(&changes);
        println!("{}", summary.commit_message(selector, &versions, base.as_deref()));
        Ok(())
    }

    pub fn rollback(&self, host: &str, offset: i32) -> Result<()> {
        if offset >= 0 {
            bail!("offset must be negative, for example -2");
        }
        let Some(_lock) = DeployLock::acquire(
            &self.config.deploy_lock_path,
            "rollback",
            LockMode::Skip,
        )? else {
            bail!("rollback skipped because another deploy owns the lock");
        };
        let target = ssh_host(&self.config, host);
        let roots = self.config.built_gcroot_dir.join(host);
        if roots.exists() {
            println!("Copying available closures to {host}...");
            for entry in fs::read_dir(roots)? {
                let entry = entry?;
                let Ok(path) = fs::canonicalize(entry.path()) else {
                    continue;
                };
                if path.exists() {
                    let _ = run_logged(
                        Command::new("nix")
                            .args(["copy", "--to", &format!("ssh://root@{target}")])
                            .arg(path),
                    );
                }
            }
        }

        let generations = run_capture(
            Command::new("ssh")
                .args(["-o", "BatchMode=yes"])
                .arg(format!("root@{target}"))
                .arg("nix-env -p /nix/var/nix/profiles/system --list-generations"),
        )?;
        if !generations.success() {
            bail!("unable to list generations on {host}:\n{}", generations.text);
        }
        let generation_numbers: Vec<_> = generations
            .text
            .lines()
            .filter_map(|line| line.split_whitespace().next()?.parse::<u64>().ok())
            .collect();
        let distance = offset.unsigned_abs() as usize;
        let generation = generation_numbers
            .get(generation_numbers.len().checked_sub(distance).context("offset exceeds available generations")?)
            .context("offset exceeds available generations")?;
        println!("Switching {host} to generation {generation}");
        let command = format!(
            "nix-env -p /nix/var/nix/profiles/system --switch-generation {generation} && /nix/var/nix/profiles/system/activate"
        );
        let output = run_logged(
            Command::new("ssh")
                .args(["-o", "BatchMode=yes"])
                .arg(format!("root@{target}"))
                .arg(command),
        )?;
        if output.success() {
            self.notifier.notify(
                &format!("🔄 Rollback: {host} → gen {generation}"),
                5,
                &format!("{host} switched to generation {generation}"),
            );
            println!("deploy-old completed for {host} -> generation {generation}");
            Ok(())
        } else {
            self.notifier.notify_email(
                &format!("❌ Rollback FAILED: {host} → gen {generation}"),
                10,
                "Remote activation failed. If store paths are missing, copy an available pinned closure and retry.",
                &deploy_log_email_body(&output, "Rollback activation log."),
            );
            bail!("remote rollback activation failed")
        }
    }

    fn accept_build(&self, host: &str, build: &BuildResult, schedule: &str) -> Option<std::path::PathBuf> {
        if build.output.success() {
            if let Some(path) = &build.system_path {
                return Some(path.clone());
            }
        }
        let title = format!("❌ {schedule}: {host} build FAILED");
        let email = deploy_log_email_body(
            &build.output,
            &format!("Build log excerpt for {host} ({schedule})."),
        );
        self.notifier.notify_email(
            &title,
            10,
            "Per-host build failed or produced no NixOS system path.",
            &email,
        );
        None
    }

    fn notify_host_failure(&self, title: &str, output: &RunOutput, heading: &str) {
        let tail = output.tail(20);
        let email = deploy_log_email_body(output, heading);
        self.notifier.notify_email(
            title,
            10,
            &format!("Last 20 lines:\n{tail}"),
            &email,
        );
    }

    fn pre_deploy_commit(&self, label: &str) -> Result<()> {
        phase(format!("{label}: committing pre-deploy state"));
        self.git(&["add", "-A"], false)?;
        self.git(
            &[
                "commit",
                "-m",
                &format!(
                    "auto: {label} {}",
                    Local::now().format("%Y-%m-%d %H:%M")
                ),
            ],
            true,
        )?;
        Ok(())
    }

    /// Compare a host's old and new closures, tolerating every way that can
    /// fail: a summary is never worth aborting a successful deployment for.
    fn host_change(&self, host: &str, previous: Option<&Path>, current: &Path) -> HostChange {
        let (packages, note) = match previous {
            None => (Vec::new(), Some("first recorded build".to_owned())),
            Some(previous) if previous == current => {
                (Vec::new(), Some("closure unchanged".to_owned()))
            }
            Some(previous) => {
                match closure_packages(previous, current, self.config.summary.max_closure_lines) {
                    Ok(packages) if packages.is_empty() => {
                        (packages, Some("no package changes".to_owned()))
                    }
                    Ok(packages) => (packages, None),
                    Err(error) => {
                        eprintln!("warning: closure diff for {host} failed: {error:#}");
                        (Vec::new(), Some("closure diff unavailable".to_owned()))
                    }
                }
            }
        };
        HostChange {
            host: host.to_owned(),
            version: self.colmena.version(host),
            packages,
            note,
        }
    }

    /// The commit a deployment is measured against: the last one this
    /// controller deployed, or the current tip the first time through.
    fn summary_base(&self) -> Option<String> {
        self.rev_parse(&self.config.summary.marker_ref)
            .or_else(|| self.rev_parse("HEAD"))
    }

    fn rev_parse(&self, reference: &str) -> Option<String> {
        let output = run_capture(
            Command::new("git")
                .args(["rev-parse", "--verify", "--quiet"])
                .arg(format!("{reference}^{{commit}}"))
                .current_dir(&self.config.repo_path),
        )
        .ok()?;
        output
            .success()
            .then(|| output.stdout.trim().to_owned())
            .filter(|revision| !revision.is_empty())
    }

    /// Summarise what a successful deployment changed and commit it.
    ///
    /// The commit is unconditional. A rebuild that only picked up new package
    /// versions edits no files, and that is exactly the deployment whose
    /// history is worth having.
    fn record_deploy(
        &self,
        label: &str,
        base: Option<&str>,
        hosts: Vec<HostChange>,
    ) -> Option<String> {
        if hosts.is_empty() {
            return None;
        }
        phase(format!("{label}: summarising {} hosts", hosts.len()));
        let versions: Vec<String> = hosts
            .iter()
            .map(|host| format!("{}: {}", host.host, host.version))
            .collect();
        let changes = DeployChanges::collect(&self.config, label, base, hosts);
        let summary = self.summarizer.summarize(&changes);
        let message = summary.commit_message(label, &versions, base);

        phase(format!("{label}: deploy summary"));
        println!("{message}");
        // A failure here must not turn a successful deployment into a failed
        // one, so it is reported and the run continues to its notifications.
        if let Err(error) = self.commit_summary(&message) {
            eprintln!("warning: failed to commit the deploy summary: {error:#}");
        }
        Some(format!(
            "{}\n\n{}",
            summary.subject,
            summary.body.trim_end()
        ))
    }

    fn commit_summary(&self, message: &str) -> Result<()> {
        self.git(&["add", "-A"], false)?;
        self.git(&["commit", "--allow-empty", "-m", message], false)?;
        self.git(&["update-ref", &self.config.summary.marker_ref, "HEAD"], true)
    }

    fn git(&self, args: &[&str], allow_failure: bool) -> Result<()> {
        let output = run_logged(Command::new("git").args(args).current_dir(&self.config.repo_path))?;
        if !output.success() && !allow_failure {
            bail!("git {} failed", args.join(" "));
        }
        Ok(())
    }
}

fn with_report(body: &str, report: Option<&str>) -> String {
    match report {
        Some(report) => format!("{body}\n\n{report}"),
        None => body.to_owned(),
    }
}

fn display_set(values: &BTreeSet<String>) -> String {
    if values.is_empty() {
        "none".to_owned()
    } else {
        values.iter().cloned().collect::<Vec<_>>().join(" ")
    }
}

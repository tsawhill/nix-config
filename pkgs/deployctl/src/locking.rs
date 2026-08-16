use std::fs::{File, OpenOptions};
use std::io::{IsTerminal, Read, Seek, SeekFrom, Write};
use std::path::Path;

use anyhow::{Context, Result};
use chrono::Local;
use fs2::FileExt;

use crate::process::phase;

#[derive(Clone, Copy, Debug)]
pub enum LockMode {
    Wait,
    Skip,
    /// Ask on a terminal whether to wait; skip when not interactive.
    Prompt,
}
/// An owned lock guard. The kernel releases the flock when this file closes.
pub struct DeployLock {
    _file: File,
}

impl DeployLock {
    pub fn acquire(path: &Path, owner: &str, mode: LockMode) -> Result<Option<Self>> {
        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .open(path)
            .with_context(|| format!("failed to open deploy lock {}", path.display()))?;

        match file.try_lock_exclusive() {
            Ok(()) => {
                stamp(&file, owner);
                Ok(Some(Self { _file: file }))
            }
            Err(_) if matches!(mode, LockMode::Skip) => {
                phase(format!(
                    "Another deploy is already running ({}); skipping {owner}",
                    holder(path)
                ));
                Ok(None)
            }
            Err(_) if matches!(mode, LockMode::Prompt) => {
                let held_by = holder(path);
                // A systemd unit has no one to answer, so degrade to skipping.
                if !std::io::stdin().is_terminal() {
                    phase(format!(
                        "Another deploy is already running ({held_by}); skipping {owner}"
                    ));
                    return Ok(None);
                }
                eprint!("Deploy already running -- {held_by}. Wait until lock clears? [y/N] ");
                let _ = std::io::stderr().flush();
                let mut answer = String::new();
                std::io::stdin()
                    .read_line(&mut answer)
                    .context("failed to read answer")?;
                if !matches!(answer.trim(), "y" | "Y" | "yes" | "Yes") {
                    phase(format!("Not waiting; skipping {owner}"));
                    return Ok(None);
                }
                phase(format!("Waiting for the deploy lock as {owner}"));
                file.lock_exclusive()
                    .with_context(|| format!("failed waiting for deploy lock as {owner}"))?;
                stamp(&file, owner);
                phase(format!("Deploy lock acquired for {owner}"));
                Ok(Some(Self { _file: file }))
            }
            Err(_) => {
                phase(format!(
                    "Another deploy is already running ({}); waiting to start {owner}",
                    holder(path)
                ));
                file.lock_exclusive()
                    .with_context(|| format!("failed waiting for deploy lock as {owner}"))?;
                stamp(&file, owner);
                phase(format!("Deploy lock acquired for {owner}"));
                Ok(Some(Self { _file: file }))
            }
        }
    }
}

/// Record who holds the lock, so a contender can name it. Best-effort: never
/// fail a deploy over lock metadata.
fn stamp(file: &File, owner: &str) {
    let mut handle = file;
    let _ = handle.seek(SeekFrom::Start(0));
    let _ = file.set_len(0);
    let _ = handle.write_all(
        format!(
            "{owner}\t{}\t{}\n",
            std::process::id(),
            Local::now().to_rfc3339()
        )
        .as_bytes(),
    );
    let _ = handle.flush();
}

/// Describe whoever currently holds the lock. Only meaningful once try_lock has
/// failed; an empty file means the holder has not stamped it yet.
fn holder(path: &Path) -> String {
    let unknown = || "unknown job".to_string();
    let mut text = String::new();
    if File::open(path)
        .and_then(|mut file| file.read_to_string(&mut text))
        .is_err()
    {
        return unknown();
    }

    let line = text.lines().next().unwrap_or_default().trim();
    if line.is_empty() {
        return unknown();
    }

    let mut fields = line.split('\t');
    let owner = fields.next().filter(|o| !o.is_empty()).map(str::to_string);
    let Some(owner) = owner else {
        return unknown();
    };

    // fields are owner, pid, start time; skip the pid.
    match fields
        .nth(1)
        .and_then(|started| chrono::DateTime::parse_from_rfc3339(started).ok())
    {
        Some(started) => {
            let minutes = (Local::now() - started.with_timezone(&Local)).num_minutes();
            if minutes >= 1 {
                format!("{owner}, started {minutes}m ago")
            } else {
                format!("{owner}, started just now")
            }
        }
        None => owner,
    }
}

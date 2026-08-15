use std::fs::{File, OpenOptions};
use std::path::Path;

use anyhow::{Context, Result};
use fs2::FileExt;

use crate::process::phase;

#[derive(Clone, Copy, Debug)]
pub enum LockMode {
    Wait,
    Skip,
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
            Ok(()) => Ok(Some(Self { _file: file })),
            Err(_) if matches!(mode, LockMode::Skip) => {
                phase(format!("Another deploy is already running; skipping {owner}"));
                Ok(None)
            }
            Err(_) => {
                phase(format!(
                    "Another deploy is already running; waiting to start {owner}"
                ));
                file.lock_exclusive()
                    .with_context(|| format!("failed waiting for deploy lock as {owner}"))?;
                phase(format!("Deploy lock acquired for {owner}"));
                Ok(Some(Self { _file: file }))
            }
        }
    }
}

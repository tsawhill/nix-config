use std::fs::{self, OpenOptions};
use std::io::{BufReader, BufWriter, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::cli::DeployGoal;
use crate::process::{phase, run_capture, timestamp};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RetryRecord {
    pub schedule: String,
    pub selector: String,
    pub host: String,
    pub system_path: PathBuf,
    pub goal: DeployGoal,
    pub build_id: String,
    pub created_at: String,
}
#[derive(Clone, Debug)]
pub struct RetryStore {
    state_dir: PathBuf,
    gcroot_dir: PathBuf,
}

impl RetryStore {
    pub fn new(state_dir: PathBuf, gcroot_dir: PathBuf) -> Self {
        Self {
            state_dir,
            gcroot_dir,
        }
    }

    pub fn record_path(&self, schedule: &str, host: &str) -> PathBuf {
        self.state_dir
            .join(sanitize_label(schedule))
            .join(format!("{}.json", sanitize_label(host)))
    }

    pub fn gcroot_path(&self, schedule: &str, host: &str) -> PathBuf {
        self.gcroot_dir
            .join(sanitize_label(schedule))
            .join(sanitize_label(host))
    }

    pub fn write(&self, record: &RetryRecord) -> Result<()> {
        if !record.system_path.exists() {
            bail!(
                "cannot queue missing system path {}",
                record.system_path.display()
            );
        }

        self.pin(record)?;
        let path = self.record_path(&record.schedule, &record.host);
        let parent = path.parent().context("retry record has no parent")?;
        fs::create_dir_all(parent)?;
        let temporary = path.with_extension(format!("json.tmp.{}", std::process::id()));
        let file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .open(&temporary)
            .with_context(|| format!("failed to create {}", temporary.display()))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer_pretty(&mut writer, record)?;
        writer.write_all(b"\n")?;
        writer.flush()?;
        fs::rename(&temporary, &path).with_context(|| {
            format!(
                "failed to atomically replace retry record {}",
                path.display()
            )
        })?;
        Ok(())
    }

    fn pin(&self, record: &RetryRecord) -> Result<()> {
        let root = self.gcroot_path(&record.schedule, &record.host);
        fs::create_dir_all(root.parent().context("retry GC root has no parent")?)?;
        remove_file_if_present(&root)?;
        let output = run_capture(
            Command::new("nix-store")
                .args(["--add-root"])
                .arg(&root)
                .args(["--indirect", "--realise"])
                .arg(&record.system_path),
        )?;
        if !output.success() {
            bail!(
                "failed to pin retry closure {}:\n{}",
                record.system_path.display(),
                output.text
            );
        }
        Ok(())
    }

    pub fn load(&self, path: &Path) -> Result<RetryRecord> {
        let file = fs::File::open(path)
            .with_context(|| format!("failed to open retry record {}", path.display()))?;
        serde_json::from_reader(BufReader::new(file))
            .with_context(|| format!("invalid retry record {}", path.display()))
    }

    pub fn paths(&self) -> Result<Vec<PathBuf>> {
        let mut paths = Vec::new();
        if !self.state_dir.exists() {
            return Ok(paths);
        }
        for schedule in fs::read_dir(&self.state_dir)? {
            let schedule = schedule?;
            if !schedule.file_type()?.is_dir() {
                continue;
            }
            for record in fs::read_dir(schedule.path())? {
                let record = record?;
                let path = record.path();
                if path.extension().and_then(|value| value.to_str()) == Some("json") {
                    paths.push(path);
                }
            }
        }
        paths.sort();
        Ok(paths)
    }

    pub fn delete(&self, schedule: &str, host: &str) -> Result<()> {
        let record = self.record_path(schedule, host);
        let root = self.gcroot_path(schedule, host);
        remove_file_if_present(&record)?;
        remove_file_if_present(&root)?;
        remove_empty_parent(&record, &self.state_dir);
        remove_empty_parent(&root, &self.gcroot_dir);
        Ok(())
    }

    pub fn clear_schedule(&self, schedule: &str) -> Result<()> {
        let label = sanitize_label(schedule);
        let state = self.state_dir.join(&label);
        let roots = self.gcroot_dir.join(label);
        if state.exists() || roots.exists() {
            phase(format!("Clearing queued retries for {schedule}"));
        }
        remove_dir_if_present(&state)?;
        remove_dir_if_present(&roots)?;
        Ok(())
    }

    /// Remove every older cadence for a host after its replacement closure has
    /// built successfully. This prevents an old Weekly retry from undoing a
    /// newer Daily activation (and vice versa).
    pub fn clear_host(&self, host: &str) -> Result<()> {
        let label = sanitize_label(host);
        let mut removed = false;
        removed |= remove_named_children(&self.state_dir, &format!("{label}.json"))?;
        removed |= remove_named_children(&self.gcroot_dir, &label)?;
        if removed {
            phase(format!("Clearing queued retry for {host}"));
        }
        Ok(())
    }

    pub fn new_record(
        &self,
        schedule: &str,
        selector: &str,
        host: &str,
        system_path: PathBuf,
        goal: DeployGoal,
        build_id: &str,
    ) -> RetryRecord {
        RetryRecord {
            schedule: schedule.to_owned(),
            selector: selector.to_owned(),
            host: host.to_owned(),
            system_path,
            goal,
            build_id: build_id.to_owned(),
            created_at: timestamp(),
        }
    }
}

pub fn sanitize_label(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || "._+-".contains(character) {
                character
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_owned()
}

fn remove_named_children(root: &Path, name: &str) -> Result<bool> {
    if !root.exists() {
        return Ok(false);
    }
    let mut removed = false;
    for directory in fs::read_dir(root)? {
        let directory = directory?;
        if !directory.file_type()?.is_dir() {
            continue;
        }
        let candidate = directory.path().join(name);
        if fs::symlink_metadata(&candidate).is_ok() {
            fs::remove_file(&candidate)?;
            removed = true;
            let _ = fs::remove_dir(directory.path());
        }
    }
    Ok(removed)
}

fn remove_file_if_present(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).with_context(|| format!("failed to remove {}", path.display())),
    }
}

fn remove_dir_if_present(path: &Path) -> Result<()> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).with_context(|| format!("failed to remove {}", path.display())),
    }
}

fn remove_empty_parent(path: &Path, boundary: &Path) {
    if let Some(parent) = path.parent() {
        if parent != boundary {
            let _ = fs::remove_dir(parent);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::sanitize_label;

    #[test]
    fn labels_are_filesystem_safe() {
        assert_eq!(sanitize_label(" @daily,@weekly "), "daily--weekly");
        assert_eq!(sanitize_label("server-nix"), "server-nix");
    }
}

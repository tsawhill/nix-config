use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::process::Command;

use anyhow::{bail, Result};
use chrono::DateTime;
use serde_json::Value;

use crate::config::Config;
use crate::process::run_capture;

/// Ceiling on the rendered package section.
///
/// `max_closure_lines` bounds one host; a twenty-host fleet run whose closures
/// diverge could still overrun the context window, so the whole section is
/// capped as well.
const MAX_PACKAGE_CHARS: usize = 8000;

/// What one host's closure gained, lost, or bumped during this deployment.
pub struct HostChange {
    pub host: String,
    pub version: String,
    pub packages: Vec<String>,
    /// Why no package list is available, when that is the interesting fact.
    pub note: Option<String>,
}

/// Everything a deployment changed, from both the repository and the store.
pub struct DeployChanges {
    pub label: String,
    pub hosts: Vec<HostChange>,
    pub flake_inputs: Vec<String>,
    pub diff_stat: String,
    pub diff_patch: String,
}

impl DeployChanges {
    pub fn collect(
        config: &Config,
        label: &str,
        base: Option<&str>,
        hosts: Vec<HostChange>,
    ) -> Self {
        let (flake_inputs, diff_stat, diff_patch) = match base {
            Some(base) => (
                flake_input_changes(config, base),
                git_diff_stat(config, base),
                git_diff_patch(config, base, config.summary.max_diff_chars),
            ),
            None => (Vec::new(), String::new(), String::new()),
        };
        Self {
            label: label.to_owned(),
            hosts,
            flake_inputs,
            diff_stat,
            diff_patch,
        }
    }

    pub fn host_names(&self) -> Vec<String> {
        self.hosts.iter().map(|host| host.host.clone()).collect()
    }

    /// Count every distinct package transition across the fleet, so a summary
    /// can say "and 34 others" without listing them.
    pub fn package_count(&self) -> usize {
        self.hosts
            .iter()
            .flat_map(|host| host.packages.iter())
            .collect::<BTreeSet<_>>()
            .len()
    }

    /// Collapse per-host package lists into shared and host-specific groups.
    ///
    /// A fleet deployment usually bumps the same packages everywhere, so
    /// repeating one nixpkgs bump twenty times would waste most of a small
    /// model's context on redundant text.
    pub fn package_section(&self) -> String {
        if self.hosts.is_empty() {
            return "No hosts deployed.\n".to_owned();
        }

        let mut owners: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
        for host in &self.hosts {
            for package in &host.packages {
                owners
                    .entry(package.as_str())
                    .or_default()
                    .insert(host.host.as_str());
            }
        }

        let total = self.hosts.len();
        let mut shared = Vec::new();
        let mut specific: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
        for (package, hosts) in &owners {
            if hosts.len() == total && total > 1 {
                shared.push(*package);
            } else {
                for host in hosts {
                    specific.entry(*host).or_default().push(*package);
                }
            }
        }

        let mut section = String::new();
        if !shared.is_empty() {
            section.push_str(&format!("All {total} hosts:\n"));
            for package in shared {
                section.push_str(&format!("  {package}\n"));
            }
        }
        for host in &self.hosts {
            let lines = specific.remove(host.host.as_str()).unwrap_or_default();
            if lines.is_empty() && host.note.is_none() {
                continue;
            }
            section.push_str(&format!("{}:\n", host.host));
            if let Some(note) = &host.note {
                section.push_str(&format!("  ({note})\n"));
            }
            for line in lines {
                section.push_str(&format!("  {line}\n"));
            }
        }
        if section.is_empty() {
            section.push_str("No package changes on any host.\n");
        }
        truncate_lines(&section, MAX_PACKAGE_CHARS)
    }

    /// Render the model's input. Sections are omitted rather than left empty so
    /// a rebuild with no repository edits reads as a pure package-bump report.
    pub fn prompt(&self) -> String {
        let mut prompt = format!(
            "Deployment: {}\nHosts: {}\n",
            self.label,
            join_or(&self.host_names(), "none")
        );

        if !self.flake_inputs.is_empty() {
            prompt.push_str("\n## Flake inputs updated\n");
            for line in &self.flake_inputs {
                prompt.push_str(line);
                prompt.push('\n');
            }
        }

        prompt.push_str("\n## Package changes (nix store diff-closures)\n");
        prompt.push_str(&self.package_section());

        if self.diff_stat.trim().is_empty() {
            prompt.push_str("\n## Configuration changes\nNo files were edited.\n");
        } else {
            prompt.push_str("\n## Configuration changes\n");
            prompt.push_str(self.diff_stat.trim_end());
            prompt.push('\n');
            if !self.diff_patch.trim().is_empty() {
                prompt.push_str("\n### Diff\n");
                prompt.push_str(self.diff_patch.trim_end());
                prompt.push('\n');
            }
        }

        prompt
    }

    /// The message used when llm-nix cannot be reached. Mechanical, but it
    /// still records exactly what a rebuild changed.
    pub fn fallback_body(&self) -> String {
        let mut body = String::new();
        if !self.flake_inputs.is_empty() {
            body.push_str("Flake inputs:\n");
            for line in &self.flake_inputs {
                body.push_str(&format!("- {line}\n"));
            }
            body.push('\n');
        }
        body.push_str("Package changes:\n");
        body.push_str(&self.package_section());
        if !self.diff_stat.trim().is_empty() {
            body.push_str("\nFiles changed:\n");
            body.push_str(self.diff_stat.trim_end());
            body.push('\n');
        }
        body
    }

    pub fn fallback_subject(&self) -> String {
        let packages = self.package_count();
        let files = self.diff_stat.lines().count().saturating_sub(1);
        let hosts = plural(self.hosts.len(), "host");
        match (packages, files) {
            (0, 0) => format!("{hosts}, no changes"),
            (0, files) => format!("{hosts}, {} changed", plural(files, "file")),
            (packages, 0) => format!("{hosts}, {} changed", plural(packages, "package")),
            (packages, files) => format!(
                "{hosts}, {} and {} changed",
                plural(packages, "package"),
                plural(files, "file")
            ),
        }
    }
}

/// Ask Nix what changed between two realised systems.
///
/// Nix emits colour escapes even when its output is a pipe, so the text is
/// cleaned before anything else looks at it.
pub fn closure_packages(previous: &Path, current: &Path, max_lines: usize) -> Result<Vec<String>> {
    if previous == current {
        return Ok(Vec::new());
    }
    let output = run_capture(
        Command::new("nix")
            .args(["store", "diff-closures"])
            .arg(previous)
            .arg(current),
    )?;
    if !output.success() {
        bail!("nix store diff-closures failed:\n{}", output.text.trim());
    }
    Ok(rank_closure_lines(&strip_ansi(&output.stdout), max_lines))
}

/// Order closure lines by how much a human cares about them, then truncate.
///
/// Version transitions matter most, additions and removals next, and pure size
/// deltas last: those are almost always rebuild noise from an unchanged package.
pub fn rank_closure_lines(text: &str, max_lines: usize) -> Vec<String> {
    let mut bumped = Vec::new();
    let mut moved = Vec::new();
    let mut resized = Vec::new();

    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if !line.contains('→') {
            resized.push(line.to_owned());
        } else if line.contains('∅') || line.contains('ε') {
            moved.push(line.to_owned());
        } else {
            bumped.push(line.to_owned());
        }
    }

    bumped.extend(moved);
    bumped.extend(resized);
    let total = bumped.len();
    if total > max_lines {
        bumped.truncate(max_lines);
        bumped.push(format!("... and {} more", total - max_lines));
    }
    bumped
}

fn strip_ansi(text: &str) -> String {
    let mut clean = String::with_capacity(text.len());
    let mut characters = text.chars();
    while let Some(character) = characters.next() {
        if character != '\u{1b}' {
            clean.push(character);
            continue;
        }
        for escaped in characters.by_ref() {
            if escaped.is_ascii_alphabetic() {
                break;
            }
        }
    }
    clean
}

fn git_diff_stat(config: &Config, base: &str) -> String {
    git_text(config, &["diff", "--stat", base, "HEAD"])
}

fn git_diff_patch(config: &Config, base: &str, max_chars: usize) -> String {
    // flake.lock is excluded deliberately: it is enormous, and every effect it
    // has already appears as a closure diff or a flake input line.
    let patch = git_text(
        config,
        &[
            "diff",
            base,
            "HEAD",
            "--",
            ".",
            ":(exclude)flake.lock",
            ":(exclude)pkgs/deployctl/Cargo.lock",
        ],
    );
    truncate_lines(&patch, max_chars)
}

/// Compare locked flake inputs between two revisions of flake.lock.
fn flake_input_changes(config: &Config, base: &str) -> Vec<String> {
    let previous = git_text(config, &["show", &format!("{base}:flake.lock")]);
    let current = match std::fs::read_to_string(config.repo_path.join("flake.lock")) {
        Ok(text) => text,
        Err(_) => return Vec::new(),
    };
    diff_flake_locks(&previous, &current)
}

pub fn diff_flake_locks(previous: &str, current: &str) -> Vec<String> {
    let (Ok(previous), Ok(current)) = (
        serde_json::from_str::<Value>(previous),
        serde_json::from_str::<Value>(current),
    ) else {
        return Vec::new();
    };

    let mut changes = Vec::new();
    let Some(nodes) = current.get("nodes").and_then(Value::as_object) else {
        return changes;
    };
    for (name, node) in nodes {
        if name == "root" {
            continue;
        }
        let old = previous.pointer(&format!("/nodes/{name}/locked"));
        let new = node.get("locked");
        let (Some(old), Some(new)) = (old, new) else {
            continue;
        };
        if locked_revision(old) == locked_revision(new) {
            continue;
        }
        changes.push(format!(
            "{name}: {} → {}",
            locked_label(old),
            locked_label(new)
        ));
    }
    changes
}

fn locked_revision(locked: &Value) -> Option<&str> {
    locked
        .get("rev")
        .or_else(|| locked.get("narHash"))
        .and_then(Value::as_str)
}

fn locked_label(locked: &Value) -> String {
    let date = locked
        .get("lastModified")
        .and_then(Value::as_i64)
        .and_then(|seconds| DateTime::from_timestamp(seconds, 0))
        .map(|time| time.format("%Y-%m-%d").to_string())
        .unwrap_or_else(|| "unknown".to_owned());
    match locked_revision(locked) {
        Some(revision) => format!("{date} ({})", short_revision(revision)),
        None => date,
    }
}

fn short_revision(revision: &str) -> String {
    revision.chars().take(8).collect()
}

fn git_text(config: &Config, args: &[&str]) -> String {
    run_capture(
        Command::new("git")
            .args(args)
            .current_dir(&config.repo_path),
    )
    .ok()
    .filter(|output| output.success())
    .map(|output| output.stdout)
    .unwrap_or_default()
}

/// Cut text to a budget on a line boundary, so a model never sees half a hunk.
pub fn truncate_lines(text: &str, max_chars: usize) -> String {
    if text.len() <= max_chars {
        return text.to_owned();
    }
    let mut kept = String::with_capacity(max_chars + 32);
    for line in text.lines() {
        if kept.len() + line.len() + 1 > max_chars {
            break;
        }
        kept.push_str(line);
        kept.push('\n');
    }
    kept.push_str("... (truncated)\n");
    kept
}

fn plural(count: usize, noun: &str) -> String {
    if count == 1 {
        format!("{count} {noun}")
    } else {
        format!("{count} {noun}s")
    }
}

pub fn join_or(values: &[String], empty: &str) -> String {
    if values.is_empty() {
        empty.to_owned()
    } else {
        values.join(" ")
    }
}

#[cfg(test)]
mod tests {
    use super::{diff_flake_locks, rank_closure_lines, truncate_lines};

    #[test]
    fn version_bumps_outrank_size_noise() {
        let diff = "source: 9.3 KiB\nlinux: 6.12.1 → 6.12.4\nghc: ∅ → 9.6.4\n";
        assert_eq!(
            rank_closure_lines(diff, 10),
            vec!["linux: 6.12.1 → 6.12.4", "ghc: ∅ → 9.6.4", "source: 9.3 KiB"]
        );
    }

    #[test]
    fn colour_escapes_never_reach_the_model() {
        let diff = "source: \u{1b}[31;1m9.3 KiB\u{1b}[0m\n";
        assert_eq!(
            rank_closure_lines(&super::strip_ansi(diff), 10),
            vec!["source: 9.3 KiB"]
        );
    }

    #[test]
    fn truncation_reports_how_much_was_dropped() {
        let diff = "a: 1 → 2\nb: 1 → 2\nc: 1 → 2\n";
        assert_eq!(
            rank_closure_lines(diff, 2),
            vec!["a: 1 → 2", "b: 1 → 2", "... and 1 more"]
        );
    }

    #[test]
    fn only_moved_flake_inputs_are_reported() {
        let previous = r#"{"nodes":{"root":{},"nixpkgs":{"locked":{"rev":"aaaaaaaaaaaa","lastModified":1786406400}},"disko":{"locked":{"rev":"cccccccccccc","lastModified":1786406400}}}}"#;
        let current = r#"{"nodes":{"root":{},"nixpkgs":{"locked":{"rev":"bbbbbbbbbbbb","lastModified":1786492800}},"disko":{"locked":{"rev":"cccccccccccc","lastModified":1786406400}}}}"#;
        assert_eq!(
            diff_flake_locks(previous, current),
            vec!["nixpkgs: 2026-08-11 (aaaaaaaa) → 2026-08-12 (bbbbbbbb)"]
        );
    }

    #[test]
    fn fallback_subjects_are_grammatical() {
        assert_eq!(super::plural(1, "host"), "1 host");
        assert_eq!(super::plural(0, "package"), "0 packages");
        assert_eq!(super::plural(6, "file"), "6 files");
    }

    #[test]
    fn truncation_stops_on_a_line_boundary() {
        let text = "first line\nsecond line\nthird line\n";
        let cut = truncate_lines(text, 20);
        assert!(cut.starts_with("first line\n"));
        assert!(cut.ends_with("... (truncated)\n"));
        assert!(!cut.contains("third"));
    }
}

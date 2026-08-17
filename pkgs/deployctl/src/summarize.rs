use std::process::Command;

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use crate::changes::DeployChanges;
use crate::config::SummaryConfig;
use crate::process::{run_with_stdin, RunOutput};

/// Written for a 7B model: short, absolute rules, and an explicit ban on the
/// two failure modes that matter here — chatty preambles and invented versions.
const SYSTEM_PROMPT: &str = "\
You write git commit messages describing NixOS deployments.

Your input has three parts: flake inputs that moved, package version changes \
produced by `nix store diff-closures`, and a git diff of the configuration \
repository.

Rules:
- Output the commit message only. No preamble, no explanation, no code fences.
- The first line is a subject under 55 characters, imperative mood, naming the \
single most significant change.
- Then one blank line, then 2 to 5 bullet points, each starting with '- '.
- Describe configuration edits by what they do, not by which file changed.
- For package bumps, name the ones a person would care about (kernel, mesa, \
nvidia, systemd, glibc, browsers, desktop) and give a count for the rest.
- Never invent a package, version, host, or change that is not in the input. \
If a section says nothing changed, say so plainly.";

pub struct Summary {
    pub subject: String,
    pub body: String,
    pub generated: bool,
}

impl Summary {
    /// A commit message with a machine-readable prefix and a trailer block, so
    /// `git log --oneline` stays scannable no matter what the model wrote.
    pub fn commit_message(&self, label: &str, versions: &[String], base: Option<&str>) -> String {
        let prefix = format!("deploy({label}): ");
        let room = 72usize.saturating_sub(prefix.len());
        let mut message = format!("{prefix}{}\n\n{}", truncate_chars(&self.subject, room), self.body.trim_end());
        if !versions.is_empty() {
            message.push_str("\n\n");
            message.push_str(&versions.join("\n"));
        }
        if let Some(base) = base {
            message.push_str(&format!("\n\nDeploy-Base: {base}"));
        }
        if !self.generated {
            message.push_str("\nDeploy-Summary: fallback (llm-nix unavailable)");
        }
        message.push('\n');
        message
    }
}

pub struct Summarizer {
    config: SummaryConfig,
}

impl Summarizer {
    pub fn new(config: SummaryConfig) -> Self {
        Self { config }
    }

    /// Summarise a deployment, degrading to a mechanical report rather than
    /// ever failing: a deploy that worked must still be recorded.
    pub fn summarize(&self, changes: &DeployChanges) -> Summary {
        if !self.config.enabled {
            return self.fallback(changes);
        }
        match self.ask(&changes.prompt()) {
            Ok(text) => match split_message(&text) {
                Some((subject, body)) => Summary {
                    subject,
                    body,
                    generated: true,
                },
                None => {
                    eprintln!("warning: {} returned an unusable summary", self.config.model);
                    self.fallback(changes)
                }
            },
            Err(error) => {
                eprintln!("warning: deploy summary unavailable: {error:#}");
                self.fallback(changes)
            }
        }
    }

    fn fallback(&self, changes: &DeployChanges) -> Summary {
        Summary {
            subject: changes.fallback_subject(),
            body: changes.fallback_body(),
            generated: false,
        }
    }

    /// Ollama's chat API over curl. curl is already a dependency for Gotify,
    /// and an HTTP crate would add a large tree for one request per deploy.
    fn ask(&self, prompt: &str) -> Result<String> {
        let request = json!({
            "model": self.config.model,
            "stream": false,
            "keep_alive": self.config.keep_alive,
            "messages": [
                { "role": "system", "content": SYSTEM_PROMPT },
                { "role": "user", "content": prompt },
            ],
            "options": {
                // Ollama defaults to a small context and silently drops the
                // rest of the prompt, which would truncate the closure diff.
                "num_ctx": self.config.num_ctx,
                "temperature": self.config.temperature,
                "num_predict": self.config.max_tokens,
            },
        });

        let output = run_with_stdin(
            Command::new("curl")
                .args(["-sS", "--fail-with-body"])
                .args(["--max-time", &self.config.request_timeout_secs.to_string()])
                .args(["-X", "POST", &self.config.endpoint])
                .args(["-H", "Content-Type: application/json"])
                .args(["--data-binary", "@-"]),
            serde_json::to_string(&request)?,
        )?;
        parse_response(&output)
    }
}

fn parse_response(output: &RunOutput) -> Result<String> {
    let body: Value = serde_json::from_str(output.stdout.trim())
        .with_context(|| format!("ollama returned non-JSON output:\n{}", output.text.trim()))?;
    if let Some(error) = body.get("error").and_then(Value::as_str) {
        bail!("ollama error: {error}");
    }
    if !output.success() {
        bail!("curl failed: {}", output.text.trim());
    }
    let content = body
        .pointer("/message/content")
        .and_then(Value::as_str)
        .context("ollama response had no message content")?;
    Ok(content.to_owned())
}

/// Split model output into a subject and body, rejecting anything that does not
/// look like a commit message.
pub fn split_message(text: &str) -> Option<(String, String)> {
    let cleaned = clean(text);
    let mut lines = cleaned.lines();
    let subject = lines.find(|line| !line.trim().is_empty())?.trim();
    if subject.len() < 8 || subject.starts_with(['-', '*', '#']) {
        return None;
    }
    let subject = subject
        .trim_start_matches("deploy:")
        .trim_start_matches("Deploy:")
        .trim()
        .trim_end_matches('.')
        .to_owned();
    let body = lines.collect::<Vec<_>>().join("\n").trim().to_owned();
    if body.is_empty() {
        return None;
    }
    Some((subject, body))
}

/// Strip the wrappers small models add even when told not to.
fn clean(text: &str) -> String {
    const PREAMBLES: &[&str] = &[
        "here is",
        "here's",
        "sure,",
        "sure!",
        "certainly",
        "commit message:",
        "summary:",
    ];

    text.lines()
        .filter(|line| !line.trim_start().starts_with("```"))
        .skip_while(|line| {
            let lowered = line.trim().to_ascii_lowercase();
            lowered.is_empty() || PREAMBLES.iter().any(|start| lowered.starts_with(start))
        })
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_owned()
}

fn truncate_chars(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_owned();
    }
    text.chars().take(max.saturating_sub(1)).collect::<String>().trim_end().to_owned() + "…"
}

#[cfg(test)]
mod tests {
    use super::{split_message, truncate_chars, Summary};

    #[test]
    fn fences_and_preambles_are_removed() {
        let reply = "Sure, here is the commit message:\n\n```\nbump the kernel to 6.12.4\n\n- linux 6.12.1 to 6.12.4\n```";
        let (subject, body) = split_message(reply).expect("message should parse");
        assert_eq!(subject, "bump the kernel to 6.12.4");
        assert_eq!(body, "- linux 6.12.1 to 6.12.4");
    }

    #[test]
    fn bullet_only_replies_are_rejected() {
        assert!(split_message("- linux 6.12.1 to 6.12.4\n- mesa bumped").is_none());
    }

    #[test]
    fn bodyless_replies_are_rejected() {
        assert!(split_message("bump the kernel to 6.12.4").is_none());
    }

    #[test]
    fn subjects_stay_within_the_git_budget() {
        let summary = Summary {
            subject: "bump the kernel, mesa, and every desktop package on the fleet".to_owned(),
            body: "- details".to_owned(),
            generated: true,
        };
        let message = summary.commit_message("Daily", &[], None);
        let subject = message.lines().next().expect("subject");
        let width = subject.chars().count();
        assert!(width <= 72, "subject was {width} characters");
        assert!(subject.starts_with("deploy(Daily): "));
    }

    #[test]
    fn fallback_messages_are_marked() {
        let summary = Summary {
            subject: "3 hosts, no changes".to_owned(),
            body: "No package changes on any host.".to_owned(),
            generated: false,
        };
        let message = summary.commit_message("Daily", &[], Some("abc1234"));
        assert!(message.contains("Deploy-Base: abc1234"));
        assert!(message.contains("Deploy-Summary: fallback"));
    }

    #[test]
    fn truncation_keeps_character_boundaries() {
        assert_eq!(truncate_chars("→→→→", 2), "→…");
    }
}

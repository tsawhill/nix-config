use std::process::Command;

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use crate::changes::DeployChanges;
use crate::config::SummaryConfig;
use crate::process::{run_with_stdin, RunOutput};

/// Tuned against qwen2.5-coder:7b on llm-nix, and the wording is load-bearing.
///
/// Two things were tried and removed because they made the output worse. A
/// worked example collapsed the model onto that example's shape: it led with
/// routine libraries and dropped everything else. Raising the bullet ceiling
/// and asking it to cover every host made it emit several subject/body
/// sections instead of one commit message. The explicit ranking below is what
/// finally stopped it spending the whole message on glibc and openssl.
const SYSTEM_PROMPT: &str = "\
You write git commit messages describing NixOS deployments.

Input sections: flake inputs that moved, package version changes from \
`nix store diff-closures`, and a git diff of the configuration repository.

What matters, most to least:
1. Configuration edits, described by what they do.
2. Packages a person notices: kernel (linux), GPU drivers (mesa, nvidia), \
browsers, desktop, database and media servers.
3. Changes affecting only one host, named with that host.
4. Routine shared libraries (glibc, openssl, curl, zstd, zlib, systemd). \
These are the LEAST interesting.

Rules:
- Output the commit message only. No preamble, no explanation, no code fences.
- Line 1: a subject under 55 characters, imperative mood, naming the most \
significant change by the ranking above, with its new version. A subject that \
names only routine libraries is wrong. A vague subject like 'update packages' \
is wrong.
- Then one blank line, then 2 to 5 bullets starting with '- '.
- A bullet that names a package must give its version transition, like \
'linux 6.16.1 -> 6.16.3'.
- Never spend a bullet on a single routine library. Collapse all of them into \
one final bullet with an exact count.
- Name the host when a change affects only that host.
- Never invent a package, version, host, or change not present in the input. \
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

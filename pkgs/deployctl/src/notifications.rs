use std::fs;
use std::io::Write;
use std::process::{Command, Stdio};

use crate::config::NotificationConfig;
use crate::process::RunOutput;

#[derive(Clone, Debug)]
pub struct Notifier {
    config: NotificationConfig,
}
impl Notifier {
    pub fn new(config: NotificationConfig) -> Self {
        Self { config }
    }

    pub fn notify(&self, title: &str, priority: u8, body: &str) {
        let Ok(token) = fs::read_to_string(&self.config.gotify_token_file) else {
            eprintln!("Gotify token unavailable; skipping notification: {title}");
            return;
        };
        let status = Command::new("curl")
            .args(["-s", "-X", "POST", &self.config.gotify_url])
            .args(["-H", &format!("X-Gotify-Key: {}", token.trim())])
            .args(["-F", &format!("title={title}")])
            .args(["-F", &format!("message={body}")])
            .args(["-F", &format!("priority={priority}")])
            .stdout(Stdio::null())
            .status();
        if let Err(error) = status {
            eprintln!("warning: Gotify notification failed: {error}");
        }
    }

    pub fn notify_email(&self, title: &str, priority: u8, body: &str, email_body: &str) {
        self.notify(title, priority, body);
        let Ok(mut child) = Command::new("msmtp")
            .arg(&self.config.recipient_email)
            .stdin(Stdio::piped())
            .spawn()
        else {
            eprintln!("warning: could not start msmtp for {title}");
            return;
        };

        if let Some(mut stdin) = child.stdin.take() {
            let message = format!(
                "To: {}\nSubject: {}\n\n{}\n",
                self.config.recipient_email, title, email_body
            );
            let _ = stdin.write_all(message.as_bytes());
        }
        if let Err(error) = child.wait() {
            eprintln!("warning: msmtp failed for {title}: {error}");
        }
    }
}

pub fn has_warnings(output: &RunOutput) -> bool {
    output
        .text
        .lines()
        .any(|line| line.contains("[WARN]") || line.contains("warning:"))
}

pub fn deploy_log_email_body(output: &RunOutput, heading: &str) -> String {
    const FAILURE_MARKERS: &[&str] = &[
        "error: Cannot build",
        "error: builder for",
        "error: cannot download",
        "Build failed:",
        "Failed:",
        "Reason:",
        "For full logs, run:",
        "nix log /nix/store/",
        "curl: (",
    ];

    let failures: Vec<_> = output
        .text
        .lines()
        .filter(|line| FAILURE_MARKERS.iter().any(|marker| line.contains(marker)))
        .rev()
        .take(80)
        .collect();
    let mut body = format!("{heading}\n\n");
    if !failures.is_empty() {
        body.push_str("Failure highlights:\n");
        for line in failures.into_iter().rev() {
            body.push_str(line);
            body.push('\n');
        }
        body.push('\n');
    }
    body.push_str("Last 120 log lines:\n");
    body.push_str(&output.tail(120));
    body
}

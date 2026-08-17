use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::mpsc;
use std::thread;

use anyhow::{Context, Result};
use chrono::{Local, SecondsFormat};

#[derive(Debug)]
pub struct RunOutput {
    pub status: ExitStatus,
    /// Standard output only. Use this for machine-readable command results.
    pub stdout: String,
    /// Combined standard output and error. Use this for logs and diagnostics.
    pub text: String,
}

impl RunOutput {
    pub fn success(&self) -> bool {
        self.status.success()
    }

    pub fn code(&self) -> i32 {
        self.status.code().unwrap_or(1)
    }

    pub fn tail(&self, count: usize) -> String {
        let lines: Vec<_> = self.text.lines().collect();
        lines[lines.len().saturating_sub(count)..].join("\n")
    }
}

pub fn timestamp() -> String {
    Local::now().to_rfc3339_opts(SecondsFormat::Secs, false)
}

pub fn phase(message: impl AsRef<str>) {
    println!("[{}] --- {} ---", timestamp(), message.as_ref());
}

/// Run a child while streaming both output pipes to the terminal and retaining
/// a combined copy for path discovery and error classification.
///
/// Two reader threads prevent a noisy stderr pipe from blocking stdout (or the
/// reverse). Their messages are serialized through one channel before logging.
pub fn run_logged(command: &mut Command) -> Result<RunOutput> {
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let display = format!("{command:?}");
    let mut child = command
        .spawn()
        .with_context(|| format!("failed to start {display}"))?;

    let stdout = child.stdout.take().context("child stdout was not piped")?;
    let stderr = child.stderr.take().context("child stderr was not piped")?;
    let (sender, receiver) = mpsc::channel::<String>();

    let stdout_thread = spawn_reader(stdout, sender.clone());
    let stderr_thread = spawn_reader(stderr, sender.clone());
    drop(sender);

    let mut text = String::new();
    for line in receiver {
        println!("[{}] {line}", timestamp());
        text.push_str(&line);
        text.push('\n');
    }

    let status = child
        .wait()
        .with_context(|| format!("failed waiting for {display}"))?;
    let _ = stdout_thread.join();
    let _ = stderr_thread.join();
    Ok(RunOutput {
        status,
        stdout: text.clone(),
        text,
    })
}

fn spawn_reader<R>(reader: R, sender: mpsc::Sender<String>) -> thread::JoinHandle<()>
where
    R: Read + Send + 'static,
{
    thread::spawn(move || {
        for line in BufReader::new(reader).lines() {
            match line {
                Ok(line) => {
                    if sender.send(line).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    })
}

/// Run a child that reads a request body on standard input.
///
/// The writer runs on its own thread so a body larger than the pipe buffer
/// cannot deadlock against a child that has not started draining it yet.
pub fn run_with_stdin(command: &mut Command, input: String) -> Result<RunOutput> {
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let display = format!("{command:?}");
    let mut child = command
        .spawn()
        .with_context(|| format!("failed to start {display}"))?;

    let mut stdin = child.stdin.take().context("child stdin was not piped")?;
    let writer = thread::spawn(move || stdin.write_all(input.as_bytes()));

    let output = child
        .wait_with_output()
        .with_context(|| format!("failed waiting for {display}"))?;
    let _ = writer.join();

    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let mut text = stdout.clone();
    text.push_str(&String::from_utf8_lossy(&output.stderr));
    Ok(RunOutput {
        status: output.status,
        stdout,
        text,
    })
}

pub fn run_capture(command: &mut Command) -> Result<RunOutput> {
    let display = format!("{command:?}");
    let output = command
        .output()
        .with_context(|| format!("failed to run {display}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let mut text = stdout.clone();
    text.push_str(&String::from_utf8_lossy(&output.stderr));
    Ok(RunOutput {
        status: output.status,
        stdout,
        text,
    })
}

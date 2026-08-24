mod changes;
mod cli;
mod colmena;
mod config;
mod controller;
mod hosts;
mod incus;
mod locking;
mod notifications;
mod process;
mod retry;
mod summarize;

use anyhow::Result;
use clap::Parser;

use crate::cli::{Cli, Command};
use crate::config::Config;
use crate::controller::Controller;

/// Parse the public CLI and dispatch one complete operation.
///
/// Keeping this boundary small makes the operational code testable without
/// manufacturing command-line arguments in every unit test.
pub fn run() -> Result<()> {
    let cli = Cli::parse();
    let config = Config::load(cli.config.as_deref())?;
    let controller = Controller::new(config);

    match cli.command {
        Command::Plan { selector, unordered } => controller.plan(&selector, !unordered),
        Command::Deploy { selector, goal } => controller.deploy_manual(&selector, goal),
        Command::Scheduled {
            schedule,
            selector,
        } => controller.deploy_scheduled(&schedule, &selector),
        Command::Retry => controller.retry_deferred(),
        Command::Summary {
            selector,
            show_prompt,
        } => controller.summarize_last(&selector, show_prompt),
        Command::Rollback { host, offset } => controller.rollback(&host, offset),
    }
}

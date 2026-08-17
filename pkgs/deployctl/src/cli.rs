use std::path::PathBuf;

use clap::{Parser, Subcommand, ValueEnum};
use serde::{Deserialize, Serialize};

#[derive(Debug, Parser)]
#[command(version, about)]
pub struct Cli {
    /// Generated non-secret configuration file.
    #[arg(long, global = true, env = "DEPLOYCTL_CONFIG")]
    pub config: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Command,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    /// Resolve selectors and print the deployment order without changing state.
    Plan {
        selector: String,

        /// Preserve lexical Colmena order instead of moving controller hosts last.
        #[arg(long)]
        unordered: bool,
    },

    /// Build and activate one host or selector manually.
    Deploy {
        selector: String,

        #[arg(default_value = "switch")]
        goal: DeployGoal,
    },

    /// Run a timer-owned cumulative deployment with durable retry records.
    Scheduled {
        schedule: String,
        selector: String,
    },

    /// Retry every deferred exact-path activation once.
    Retry,

    /// Summarise the last recorded build without deploying or committing.
    Summary {
        #[arg(default_value = "@daily")]
        selector: String,

        /// Print the text sent to the model as well as its reply.
        #[arg(long)]
        show_prompt: bool,
    },

    /// Activate an older generation on a remote host.
    Rollback {
        host: String,

        /// Negative generation offset, such as -2 for the previous generation.
        #[arg(allow_hyphen_values = true)]
        offset: i32,
    },
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, ValueEnum)]
#[serde(rename_all = "lowercase")]
pub enum DeployGoal {
    #[default]
    Switch,
    Boot,
    Test,
}

impl DeployGoal {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Switch => "switch",
            Self::Boot => "boot",
            Self::Test => "test",
        }
    }
}

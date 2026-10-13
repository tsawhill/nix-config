mod hidraw;
mod mchose;

use clap::{Parser, Subcommand};
use hidraw::{HidRaw, Node};
use serde::Deserialize;
use std::collections::HashMap;
use std::io;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::Ordering;
use std::thread::sleep;
use std::time::{Duration, Instant};

const SCAN: Duration = Duration::from_secs(2);
const POLL: Duration = Duration::from_secs(5);
const LOCK_WAIT: Duration = Duration::from_secs(3);

#[derive(Parser)]
#[command(about = "Declarative settings for USB mice and keyboards")]
struct Cli {
    /// Print every frame sent to and received from a device.
    #[arg(long, global = true)]
    trace: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Apply the config to each device once it answers after being plugged in.
    Daemon {
        #[arg(long)]
        config: PathBuf,
    },
    /// Apply the config once to every online device.
    Apply {
        #[arg(long)]
        config: PathBuf,
        /// Show what would change without writing anything.
        #[arg(long)]
        dry_run: bool,
    },
    /// Validate a config file.
    Check {
        #[arg(long)]
        config: PathBuf,
    },
    /// Print each online device's settings and a matching Nix snippet.
    Show,
    /// Mouse battery as JSON for the bar; an empty line when no mouse is online.
    Battery,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Config {
    #[serde(default)]
    dry_run: bool,
    mchose_m7_ultra: Option<mchose::Settings>,
}

fn load(path: &Path) -> Result<Config, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let config: Config = serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
    if let Some(s) = &config.mchose_m7_ultra {
        s.validate().map_err(|e| format!("mchose-m7-ultra: {e}"))?;
    }
    Ok(config)
}

fn mice() -> Vec<Node> {
    hidraw::nodes().into_iter().filter(mchose::is_config_node).collect()
}

fn print_plan(dev: &Path, plan: &mchose::Plan, verb: &str) {
    if plan.changes.is_empty() {
        eprintln!("{}: already matches the config", dev.display());
    }
    for change in &plan.changes {
        eprintln!("{}: {verb} {change}", dev.display());
    }
    for note in &plan.notes {
        eprintln!("{}: note: {note}", dev.display());
    }
}

/// The mouse's identity once it's online, or None while it's idle, asleep or off.
fn online(dev: &HidRaw) -> io::Result<Option<mchose::Identity>> {
    Ok(mchose::identity(dev)?.filter(|id| id.connected))
}

/// Bring one online mouse to the config, or just report in a dry run.
/// Runs once per plug, so lift-off (which can't be read back) is always written.
fn reconcile(path: &Path, dev: &HidRaw, id: &mchose::Identity, config: &Config, dry_run: bool) -> io::Result<()> {
    if id.id != mchose::M7_ULTRA {
        eprintln!("{}: MCHOSE device id {} has no driver yet, leaving it alone", path.display(), id.id);
        return Ok(());
    }
    let Some(settings) = &config.mchose_m7_ultra else {
        eprintln!("{}: M7 Ultra online, nothing declared for it", path.display());
        return Ok(());
    };
    if dry_run {
        let obs = mchose::observe(dev)?;
        for line in mchose::summary(&obs) {
            eprintln!("{}: {line}", path.display());
        }
        print_plan(path, &mchose::plan(settings, &obs, false), "would change");
    } else {
        print_plan(path, &mchose::apply(dev, settings, false)?, "changed");
    }
    Ok(())
}

/// Per plugged-in node: poll until the mouse answers, apply once, then leave it
/// alone so an idle mouse isn't kept awake.
#[derive(Default)]
struct Seen {
    done: bool,
    failures: u32,
    next: Option<Instant>,
}

/// True once the mouse answered and the config was applied.
fn poll(node: &Node, config: &Config) -> io::Result<bool> {
    let dev = HidRaw::open_locked(&node.dev, LOCK_WAIT)?;
    let Some(id) = online(&dev)? else {
        return Ok(false);
    };
    eprintln!("{}: mouse online ({}% battery)", node.dev.display(), id.battery);
    reconcile(&node.dev, &dev, &id, config, config.dry_run)?;
    Ok(true)
}

fn daemon(config: &Config) -> ExitCode {
    let mode = if config.dry_run { " (dry run: nothing is written)" } else { "" };
    eprintln!("periph: watching for devices{mode}");
    let mut seen: HashMap<(PathBuf, (u64, i64, i64)), Seen> = HashMap::new();
    loop {
        let nodes = mice();
        seen.retain(|(dev, stamp), _| nodes.iter().any(|n| &n.dev == dev && &n.stamp == stamp));
        let now = Instant::now();
        for node in &nodes {
            let state = seen.entry((node.dev.clone(), node.stamp)).or_default();
            if state.done || state.next.is_some_and(|t| now < t) {
                continue;
            }
            state.next = Some(now + POLL);
            match poll(node, config) {
                Ok(done) => state.done = done,
                Err(e) => {
                    state.failures += 1;
                    eprintln!("{}: {e}", node.dev.display());
                    // Don't keep rewriting a mouse that won't settle.
                    if state.failures >= 3 {
                        eprintln!("{}: giving up until it's plugged in again", node.dev.display());
                        state.done = true;
                    }
                }
            }
        }
        sleep(SCAN);
    }
}

fn apply_once(config: &Config, dry_run: bool) -> ExitCode {
    let mut ok = true;
    for node in mice() {
        let result = HidRaw::open_locked(&node.dev, LOCK_WAIT).and_then(|dev| match online(&dev)? {
            Some(id) => reconcile(&node.dev, &dev, &id, config, dry_run),
            None => {
                eprintln!("{}: mouse offline or asleep; move it and try again", node.dev.display());
                Ok(())
            }
        });
        if let Err(e) = result {
            eprintln!("{}: {e}", node.dev.display());
            ok = false;
        }
    }
    if ok {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn show() -> ExitCode {
    let nodes = mice();
    if nodes.is_empty() {
        eprintln!("no supported devices found");
    }
    for node in nodes {
        println!("{} ({:04x}:{:04x})", node.dev.display(), node.vid, node.pid);
        let result = HidRaw::open_locked(&node.dev, LOCK_WAIT).and_then(|dev| {
            if online(&dev)?.is_none() {
                println!("  mouse offline or asleep; move it and try again\n");
                return Ok(());
            }
            let obs = mchose::observe(&dev)?;
            for line in mchose::summary(&obs) {
                println!("  {line}");
            }
            println!("\n{}\n", mchose::nix(&obs));
            Ok(())
        });
        if let Err(e) = result {
            println!("  error: {e}\n");
        }
    }
    ExitCode::SUCCESS
}

fn battery() -> ExitCode {
    for node in mice() {
        let result = HidRaw::open_locked(&node.dev, LOCK_WAIT).and_then(|dev| online(&dev));
        match result {
            Ok(Some(id)) if id.vid == 0x5253 && id.battery <= 100 => {
                println!("{}", mchose::battery_json(&id));
                return ExitCode::SUCCESS;
            }
            Ok(_) => {}
            Err(e) => eprintln!("{}: {e}", node.dev.display()),
        }
    }
    println!();
    ExitCode::SUCCESS
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    mchose::TRACE.store(cli.trace, Ordering::Relaxed);
    let with_config = |path: &Path, run: &dyn Fn(&Config) -> ExitCode| match load(path) {
        Ok(config) => run(&config),
        Err(e) => {
            eprintln!("{e}");
            ExitCode::FAILURE
        }
    };
    match cli.command {
        Command::Daemon { config } => with_config(&config, &daemon),
        Command::Apply { config, dry_run } => with_config(&config, &|c| apply_once(c, dry_run || c.dry_run)),
        Command::Check { config } => with_config(&config, &|_| ExitCode::SUCCESS),
        Command::Show => show(),
        Command::Battery => battery(),
    }
}

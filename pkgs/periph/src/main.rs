mod hidraw;
mod mchose;
mod rongyuan;

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
    boyi_h60pro: Option<rongyuan::Settings>,
}

fn load(path: &Path) -> Result<Config, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let config: Config = serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
    if let Some(s) = &config.mchose_m7_ultra {
        s.validate().map_err(|e| format!("mchose-m7-ultra: {e}"))?;
    }
    if let Some(s) = &config.boyi_h60pro {
        s.validate().map_err(|e| format!("boyi-h60pro: {e}"))?;
    }
    Ok(config)
}

fn mice() -> Vec<Node> {
    hidraw::nodes().into_iter().filter(mchose::is_config_node).collect()
}

fn devices() -> Vec<Node> {
    hidraw::nodes().into_iter().filter(|n| mchose::is_config_node(n) || rongyuan::is_config_node(n)).collect()
}

/// Bring one keyboard to the config, or just report in a dry run.
fn reconcile_keyboard(node: &Node, config: &Config, dry_run: bool) -> io::Result<()> {
    let path = node.dev.display();
    let kb = match rongyuan::open(node)? {
        rongyuan::Opened::Known(kb) => kb,
        rongyuan::Opened::Unknown(id) => {
            eprintln!("{path}: RongYuan device id {id} has no key grid yet, leaving it alone");
            return Ok(());
        }
    };
    let Some(settings) = &config.boyi_h60pro else {
        eprintln!("{path}: {} online, nothing declared for it", kb.model.name);
        return Ok(());
    };
    let dry_run = dry_run || settings.dry_run;
    let changes = if dry_run {
        let obs = kb.observe()?;
        for line in kb.summary(&obs) {
            eprintln!("{path}: {line}");
        }
        kb.plan(settings, &obs).changes
    } else {
        kb.apply(settings)?
    };
    if changes.is_empty() {
        eprintln!("{path}: already matches the config");
    }
    let verb = if dry_run { "would change" } else { "changed" };
    for change in changes {
        eprintln!("{path}: {verb} {change}");
    }
    Ok(())
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
fn reconcile(node: &Node, dev: &HidRaw, id: &mchose::Identity, config: &Config, dry_run: bool) -> io::Result<()> {
    let path = node.dev.as_path();
    // Over the cable the node carries the mouse's own ID; a dongle has its own.
    let wired = node.pid == id.id;
    if id.id != mchose::M7_ULTRA {
        eprintln!("{}: MCHOSE device id {} has no driver yet, leaving it alone", path.display(), id.id);
        return Ok(());
    }
    let Some(settings) = &config.mchose_m7_ultra else {
        eprintln!("{}: M7 Ultra online, nothing declared for it", path.display());
        return Ok(());
    };
    if dry_run {
        let obs = mchose::observe(dev, id, wired)?;
        for line in mchose::summary(&obs) {
            eprintln!("{}: {line}", path.display());
        }
        print_plan(path, &mchose::plan(settings, &obs, false), "would change");
    } else {
        print_plan(path, &mchose::apply(dev, settings, id, wired, false)?, "changed");
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

/// True once the device answered and the config was applied.
fn poll(node: &Node, config: &Config) -> io::Result<bool> {
    if rongyuan::is_config_node(node) {
        reconcile_keyboard(node, config, config.dry_run)?;
        return Ok(true);
    }
    let dev = HidRaw::open_locked(&node.dev, LOCK_WAIT)?;
    let Some(id) = online(&dev)? else {
        return Ok(false);
    };
    eprintln!("{}: mouse online ({}% battery)", node.dev.display(), id.battery);
    reconcile(node, &dev, &id, config, config.dry_run)?;
    Ok(true)
}

fn daemon(config: &Config) -> ExitCode {
    let mode = if config.dry_run { " (dry run: nothing is written)" } else { "" };
    eprintln!("periph: watching for devices{mode}");
    let mut seen: HashMap<(PathBuf, (u64, i64, i64)), Seen> = HashMap::new();
    loop {
        let nodes = devices();
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
    for node in devices() {
        if rongyuan::is_config_node(&node) {
            if let Err(e) = reconcile_keyboard(&node, config, dry_run) {
                eprintln!("{}: {e}", node.dev.display());
                ok = false;
            }
            continue;
        }
        let result = HidRaw::open_locked(&node.dev, LOCK_WAIT).and_then(|dev| match online(&dev)? {
            Some(id) => reconcile(&node, &dev, &id, config, dry_run),
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

fn show_keyboard(node: &Node) -> io::Result<()> {
    match rongyuan::open(node)? {
        rongyuan::Opened::Unknown(id) => println!("  RongYuan device id {id}: no key grid for it yet\n"),
        rongyuan::Opened::Known(kb) => {
            let obs = kb.observe()?;
            for line in kb.summary(&obs) {
                println!("  {line}");
            }
            println!("\n{}\n", kb.nix(&obs));
        }
    }
    Ok(())
}

fn show() -> ExitCode {
    let nodes = devices();
    if nodes.is_empty() {
        eprintln!("no supported devices found");
    }
    for node in nodes {
        println!("{} ({:04x}:{:04x})", node.dev.display(), node.vid, node.pid);
        if rongyuan::is_config_node(&node) {
            if let Err(e) = show_keyboard(&node) {
                println!("  error: {e}\n");
            }
            continue;
        }
        let result = HidRaw::open_locked(&node.dev, LOCK_WAIT).and_then(|dev| {
            let Some(id) = online(&dev)? else {
                println!("  mouse offline or asleep; move it and try again\n");
                return Ok(());
            };
            let obs = mchose::observe(&dev, &id, node.pid == id.id)?;
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

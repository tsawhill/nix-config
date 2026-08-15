use std::collections::BTreeSet;
use std::process::Command;

use anyhow::{bail, Context, Result};

use crate::config::Config;
use crate::process::run_capture;

pub fn list_all(config: &Config) -> Result<Vec<String>> {
    eval_hosts(
        config,
        r#"hive: builtins.filter (n: n != "meta") (builtins.attrNames hive)"#,
    )
}

pub fn list_for_tag(config: &Config, tag: &str) -> Result<Vec<String>> {
    let expression = format!(
        r#"hive: builtins.filter (n: n != "meta" && builtins.elem {} ((builtins.getAttr n hive).deployment.tags or [])) (builtins.attrNames hive)"#,
        serde_json::to_string(tag)?
    );
    eval_hosts(config, &expression)
}

fn eval_hosts(config: &Config, expression: &str) -> Result<Vec<String>> {
    let output = run_capture(
        Command::new("nix")
            .args(["eval", "--json", &format!("{}#colmena", config.flake_uri)])
            .args(["--apply", expression])
            .current_dir(&config.repo_path),
    )?;
    if !output.success() {
        bail!("failed to evaluate Colmena hosts:\n{}", output.text);
    }
    serde_json::from_str(&output.stdout)
        .context("Colmena host evaluation did not return a JSON list")
}

pub fn expand_selector(config: &Config, selector: &str) -> Result<Vec<String>> {
    // Tag-only schedules avoid the extra full-hive evaluation. Resolve the
    // complete host set lazily only when a literal hostname must be checked.
    let mut known: Option<BTreeSet<String>> = None;
    let mut selected = BTreeSet::new();

    for item in selector.split(',').filter(|item| !item.is_empty()) {
        if let Some(tag) = item.strip_prefix('@') {
            selected.extend(list_for_tag(config, tag)?);
        } else {
            if known.is_none() {
                known = Some(list_all(config)?.into_iter().collect());
            }
            if known.as_ref().is_some_and(|hosts| hosts.contains(item)) {
                selected.insert(item.to_owned());
            }
        }
    }

    Ok(selected.into_iter().collect())
}

/// Move infrastructure that can interrupt the controller to the safe tail.
pub fn controller_last(mut hosts: Vec<String>) -> Vec<String> {
    let include_build = remove_host(&mut hosts, "build-nix");
    let include_server = remove_host(&mut hosts, "server-nix");
    if include_build {
        hosts.push("build-nix".to_owned());
    }
    if include_server {
        hosts.push("server-nix".to_owned());
    }
    hosts
}

fn remove_host(hosts: &mut Vec<String>, target: &str) -> bool {
    let before = hosts.len();
    hosts.retain(|host| host != target);
    hosts.len() != before
}

pub fn ssh_host(config: &Config, host: &str) -> String {
    if host.contains('.') {
        host.to_owned()
    } else {
        format!("{}.{}", host, config.lan_domain)
    }
}

#[cfg(test)]
mod tests {
    use super::controller_last;

    #[test]
    fn controller_hosts_are_stable_and_last() {
        let hosts = vec![
            "build-nix".into(),
            "adguard-nix".into(),
            "server-nix".into(),
            "vaultwarden-nix".into(),
        ];
        assert_eq!(
            controller_last(hosts),
            vec![
                "adguard-nix",
                "vaultwarden-nix",
                "build-nix",
                "server-nix"
            ]
        );
    }

    #[test]
    fn absent_controller_hosts_are_not_added() {
        assert_eq!(
            controller_last(vec!["oracle-1-nix".into()]),
            vec!["oracle-1-nix"]
        );
    }
}

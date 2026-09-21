use std::collections::{BTreeMap, BTreeSet};
use std::process::Command;

use anyhow::{bail, Context, Result};

use crate::config::Config;
use crate::process::run_capture;

/// Read the raw hive's names and tags once, without evaluating NixOS systems.
/// The same inventory drives every selector and removed-host root cleanup.
pub struct HostInventory(BTreeMap<String, Vec<String>>);

impl HostInventory {
    pub fn load(config: &Config, flake_uri: &str) -> Result<Self> {
        let output = run_capture(
            Command::new("nix")
                .args(["eval", "--json", "--no-update-lock-file"])
                .args(["--option", "pure-eval", "true"])
                .arg(format!("{flake_uri}#colmena"))
                .args([
                    "--apply",
                    r#"hive: builtins.mapAttrs (_: node: node.deployment.tags or []) (builtins.removeAttrs hive ["meta" "defaults" "network"])"#,
                ])
                .current_dir(&config.repo_path),
        )?;
        if !output.success() {
            bail!("failed to evaluate Colmena hosts:\n{}", output.text);
        }
        let hosts: BTreeMap<String, Vec<String>> = serde_json::from_str(&output.stdout)
            .context("Colmena host evaluation did not return a name/tag map")?;
        // Names become flake attribute selectors and profile directory names.
        for name in hosts.keys() {
            anyhow::ensure!(
                !name.is_empty()
                    && name
                        .bytes()
                        .all(|c| c.is_ascii_alphanumeric() || b"-_.".contains(&c))
                    && name != "."
                    && name != "..",
                "unsupported Colmena host name {name:?}"
            );
        }
        Ok(Self(hosts))
    }

    pub fn names(&self) -> BTreeSet<String> {
        self.0.keys().cloned().collect()
    }

    pub fn select(&self, selector: &str) -> Vec<String> {
        let mut selected = BTreeSet::new();
        for item in selector.split(',').filter(|item| !item.is_empty()) {
            if let Some(tag) = item.strip_prefix('@') {
                selected.extend(
                    self.0
                        .iter()
                        .filter(|(_, tags)| tags.iter().any(|candidate| candidate == tag))
                        .map(|(name, _)| name.clone()),
                );
            } else if self.0.contains_key(item) {
                selected.insert(item.to_owned());
            }
        }
        selected.into_iter().collect()
    }
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
    use super::{controller_last, HostInventory};

    #[test]
    fn inventory_expands_all_tags_and_names_without_duplicates() {
        let inventory = HostInventory(
            serde_json::from_str(
                r#"{
            "a": ["daily", "weekly"], "b": ["weekly"], "c": []
        }"#,
            )
            .unwrap(),
        );
        assert_eq!(
            inventory.select("@daily,@weekly,a,c,,unknown,@unknown"),
            vec!["a", "b", "c"]
        );
        assert_eq!(inventory.select("@daily"), vec!["a"]);
        assert_eq!(
            inventory.names().into_iter().collect::<Vec<_>>(),
            vec!["a", "b", "c"]
        );
    }

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
            vec!["adguard-nix", "vaultwarden-nix", "build-nix", "server-nix"]
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

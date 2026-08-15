use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Clone, Debug, Deserialize)]
pub struct Config {
    pub repo_path: PathBuf,
    pub flake_uri: String,
    pub retry_state_dir: PathBuf,
    pub retry_gcroot_dir: PathBuf,
    pub built_gcroot_dir: PathBuf,
    pub deploy_lock_path: PathBuf,
    pub system_profile: PathBuf,
    pub lan_domain: String,
    pub per_host_build_timeout: String,
    pub apply_timeout: String,
    pub keep_roots: usize,
    pub notifications: NotificationConfig,
    #[serde(default)]
    pub wol_macs: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct NotificationConfig {
    pub gotify_url: String,
    pub gotify_token_file: PathBuf,
    pub recipient_email: String,
}

impl Config {
    pub fn load(path: Option<&Path>) -> Result<Self> {
        let path = path.unwrap_or_else(|| Path::new("/etc/deployctl.json"));
        let bytes = fs::read(path)
            .with_context(|| format!("failed to read deployctl config at {}", path.display()))?;
        serde_json::from_slice(&bytes)
            .with_context(|| format!("invalid deployctl config at {}", path.display()))
    }
}

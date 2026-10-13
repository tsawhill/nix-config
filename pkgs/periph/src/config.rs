//! The JSON config the home-manager module writes.

use crate::{mchose, rongyuan};
use serde::Deserialize;
use std::path::Path;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Config {
    #[serde(default)]
    pub dry_run: bool,
    pub mchose_m7_ultra: Option<mchose::Settings>,
    pub boyi_h60pro: Option<rongyuan::Settings>,
}

pub fn load(path: &Path) -> Result<Config, String> {
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

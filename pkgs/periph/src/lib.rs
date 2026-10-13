//! Device drivers and config shared by the `periph` CLI/service and `periph-gui`.

pub mod config;
pub mod hidraw;
pub mod mchose;
pub mod mchose_buttons;
pub mod rongyuan;

use hidraw::Node;

/// Every plugged-in node a driver here knows how to configure.
pub fn devices() -> Vec<Node> {
    hidraw::nodes().into_iter().filter(|n| mchose::is_config_node(n) || rongyuan::is_config_node(n)).collect()
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.home-assistant;
in
{
  services.home-assistant = {
    enable = true;
    openFirewall = true;

    # UI-configured integrations also need their dependencies packaged.
    # HVAC must work without internet access; do not use cloud scenes.
    extraComponents = [
      "default_config"
      "esphome"
      "met"
    ];
    customComponents = [ pkgs.home-assistant-custom-components.tuya_local ];

    config = {
      default_config = { };
      homeassistant = {
        name = "Home";
        time_zone = config.time.timeZone;
        unit_system = "us_customary";
      };
      http.server_port = 8123;
      recorder.purge_keep_days = 14;

      # Declarative automations can be appended by other Nix modules. Keep
      # UI experiments separate so deployments never overwrite them.
      "automation manual" = [ ];
      "automation ui" = "!include automations.yaml";
      "script ui" = "!include scripts.yaml";
      "scene ui" = "!include scenes.yaml";
    };
  };

  # Initialize includes before the first start; preserve subsequent UI edits.
  systemd.services.home-assistant.preStart = lib.mkBefore ''
    for file in automations.yaml scenes.yaml; do
      if [ ! -e ${lib.escapeShellArg cfg.configDir}/"$file" ]; then
        printf '[]\n' > ${lib.escapeShellArg cfg.configDir}/"$file"
      fi
    done
    if [ ! -e ${lib.escapeShellArg cfg.configDir}/scripts.yaml ]; then
      printf '{}\n' > ${lib.escapeShellArg cfg.configDir}/scripts.yaml
    fi
  '';

  # mDNS discovery on the bridged LAN (no host USB/Bluetooth passthrough).
  networking.firewall.allowedUDPPorts = [ 5353 ];
}

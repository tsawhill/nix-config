{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.home-assistant;

  # Arbitrary; SmartIR only needs a code not shipped upstream.
  daikinDeviceCode = 9000;

  # SmartIR reads device files from inside its own component directory, which
  # is read-only here, and downloads from GitHub when one is missing. Baking
  # ours in avoids both. Omitting a top-level `smartir:` section also leaves
  # its update check unregistered, so it never reaches the network.
  smartir = pkgs.home-assistant-custom-components.smartir.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      install -Dm444 ${./daikin-arc452a21.json} \
        $out/custom_components/smartir/codes/climate/${toString daikinDeviceCode}.json
    '';
  });

  # SmartIR's Broadlink controller is not Broadlink-specific: with Base64 codes
  # it calls remote.send_command with a "b64:" prefix on whatever entity it is
  # given, which is exactly the convention tuya-local implements.
  mkRoomClimate = slug: name: {
    platform = "smartir";
    inherit name;
    unique_id = "${slug}_ac";
    device_code = daikinDeviceCode;
    controller_data = "remote.ac_controller_${slug}";
    # The head unit senses return air near the ceiling, which is why its own
    # setpoints read as inaccurate. Drive the loop from the room sensor.
    temperature_sensor = "sensor.ac_controller_${slug}_temperature";
    humidity_sensor = "sensor.ac_controller_${slug}_humidity";
  };
in
{
  services.home-assistant = {
    enable = true;
    openFirewall = true;

    # UI-configured integrations also need their dependencies packaged.
    # HVAC must work without internet access; do not use cloud scenes.
    extraComponents = [
      "climate"
      "default_config"
      "esphome"
      "met"
    ];
    customComponents = [
      pkgs.home-assistant-custom-components.tuya_local
      smartir
    ];

    config = {
      default_config = { };
      homeassistant = {
        name = "Home";
        time_zone = config.time.timeZone;
        unit_system = "us_customary";
      };
      http.server_port = 8123;
      recorder.purge_keep_days = 14;

      # Slugs follow the Tuya Local device names, which set the entity ids.
      climate = [
        (mkRoomClimate "office" "Office AC")
        (mkRoomClimate "bedroom" "Bedroom AC")
        (mkRoomClimate "living_room" "Living Room AC")
      ];

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

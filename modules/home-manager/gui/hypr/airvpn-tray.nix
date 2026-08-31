{
  lib,
  config,
  osConfig,
  pkgs,
  ...
}:

let
  cfg = config.my.hypr.airvpnTray;

  # Null on hosts that never import the AirVPN NixOS module (the laptop shares
  # this Hyprland bundle but has no AirVPN profiles).
  airvpnCfg = osConfig.my.network.airvpn or null;

  airvpn-tray = pkgs.callPackage ../../../../pkgs/airvpn-tray/package.nix { };

  trayConfig = pkgs.writeText "airvpn-tray.json" (
    builtins.toJSON {
      interface = airvpnCfg.interfaceName;
      inherit (airvpnCfg) endpoints;
      publicIpUrl = cfg.exitIpUrl;
      commands.nmcli = "${pkgs.networkmanager}/bin/nmcli";
    }
  );
in
{
  options.my.hypr.airvpnTray = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = airvpnCfg != null && airvpnCfg.enable;
      description = "Show an AirVPN server picker in the system tray.";
    };

    exitIpUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "https://api.ipify.org";
      description = ''
        Queried once after each connection change to display the current exit IP.
        Null disables the lookup entirely, so the applet never reaches the network
        on its own.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && config.wayland.windowManager.hyprland.enable) {
    home.packages = [ airvpn-tray ];

    systemd.user.services.airvpn-tray = {
      Unit = {
        Description = "AirVPN tray applet";
        After = [ "wayland-session@hyprland.desktop.target" ];
        PartOf = [ "wayland-session@hyprland.desktop.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe airvpn-tray} --config ${trayConfig}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install.WantedBy = [ "wayland-session@hyprland.desktop.target" ];
    };
  };
}

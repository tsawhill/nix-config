{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  cfg = config.my.usbipTray;
  app = pkgs.callPackage ../../../pkgs/usbip-tray/package.nix { };
  hostname = osConfig.networking.hostName;
  settings = pkgs.writeText "usbip-tray.json" (
    builtins.toJSON {
      recipients = lib.filterAttrs (name: _: name != hostname) cfg.recipients;
      ssh = "${pkgs.openssh}/bin/ssh";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      systemdRun = "${pkgs.systemd}/bin/systemd-run";
    }
  );
  hypr = config.wayland.windowManager.hyprland.enable or false;
  target = if hypr then "wayland-session@hyprland.desktop.target" else "graphical-session.target";
in
{
  options.my.usbipTray = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = (osConfig.my.usbip.enable or false) && (osConfig.my.usbip.exporter or false);
      description = "Show the USB port sharing applet.";
    };
    recipients = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            ssh = lib.mkOption {
              type = lib.types.str;
              description = "SSH user@host for this receiver.";
            };
            container = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Use the receiver's configured Incus container.";
            };
          };
        }
      );
      default = {
        taylor-desktop-nix.ssh = "taylor@taylor-desktop-nix.lan";
        taylor-cube-nix.ssh = "taylor@taylor-cube-nix.lan";
        sunshine-nix = {
          ssh = "taylor@server-nix.lan";
          container = true;
        };
      };
      description = "Named USB recipients (the current host is hidden).";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ app ];
    xdg.desktopEntries.usbip-tray = {
      name = "USB Sharing";
      comment = "Share local USB ports with another computer";
      exec = "${lib.getExe app} --config ${settings}";
      icon = "drive-removable-media-usb";
      categories = [
        "System"
        "Utility"
      ];
      terminal = false;
    };
    systemd.user.services.usbip-tray = {
      Unit = {
        Description = "USB port sharing tray";
        After = [ target ];
        PartOf = [ target ];
      };
      Service = {
        ExecStart = "${lib.getExe app} --config ${settings}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ target ];
    };
  };
}

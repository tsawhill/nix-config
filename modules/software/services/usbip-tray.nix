{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.usbip;
  usbip = config.boot.kernelPackages.usbip;
  settings = pkgs.writeText "usbip-helper.json" (
    builtins.toJSON {
      inherit (cfg) exporter receiver;
      container = cfg.containerRecipient;
      usbip = "${usbip}/bin/usbip";
      incus = "${pkgs.incus}/bin/incus";
    }
  );
  helper = pkgs.writeShellScriptBin "usbip-tray-helper" ''
    exec ${pkgs.python3}/bin/python3 -I ${../../../pkgs/usbip-tray/helper.py} ${settings} "$@"
  '';
in
{
  options.my.usbip = {
    enable = lib.mkEnableOption "USB/IP sharing over SSH";
    exporter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow local USB devices to be shared.";
    };
    receiver = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow USB devices to be received over SSH.";
    };
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "taylor" ];
      description = "Users allowed to manage USB/IP leases.";
    };
    containerRecipient = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Incus container allowed to receive imported USB device nodes.";
    };
  };
  config = lib.mkIf cfg.enable {
    boot.kernelModules = lib.optional cfg.exporter "usbip_host" ++ lib.optional cfg.receiver "vhci_hcd";
    environment.systemPackages = [ helper ];
    systemd.tmpfiles.rules = [ "d /run/usbip-tray 0700 root root -" ];
    security.sudo.extraRules = [
      {
        inherit (cfg) users;
        commands = [
          {
            command = "${helper}/bin/usbip-tray-helper";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
    systemd.services.usbip-tray-server = lib.mkIf cfg.exporter {
      description = "USB/IP exporter (SSH tunnels only)";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      serviceConfig = {
        ExecStart = "${usbip}/bin/usbipd -4";
        Restart = "on-failure";
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
    # No USB/IP firewall port is opened; sshd is the only network entry point.
  };
}

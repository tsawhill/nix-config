{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.software.lan-launch.enable =
    lib.mkEnableOption "lan-launch (run apps over LAN, bypassing VPN)";

  config = lib.mkIf config.software.lan-launch.enable {
    programs.firejail.enable = true;

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "lan-launch" ''
        if [ $# -lt 2 ]; then
          echo "Usage: lan-launch <interface> <command...>" >&2
          exit 1
        fi
        iface="$1"
        shift
        exec firejail --net="$iface" "$@"
      '')
    ];
  };
}

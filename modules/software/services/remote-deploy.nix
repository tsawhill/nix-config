{ pkgs, ... }:

let
  buildHost = "build-nix";

  remoteDeployCmd = pkgs.writeShellScriptBin "remote-deploy" ''
    set -euo pipefail

    if [ $# -lt 1 ]; then
      echo "Usage: remote-deploy <host|@tag> [goal]"
      echo "  Examples:"
      echo "    remote-deploy taylor-laptop-nix"
      echo "    remote-deploy taylor-desktop-nix boot"
      echo "    remote-deploy @weekly"
      exit 1
    fi

    exec ${pkgs.openssh}/bin/ssh -t root@${buildHost} deploy "$@"
  '';
in
{
  environment.systemPackages = [ remoteDeployCmd ];
}

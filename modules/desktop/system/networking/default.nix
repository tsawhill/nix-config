{ pkgs, ... }:
{
  networking.hostName = "taylor-nix"; # Define your hostname.
  networking.hostId = "34801239";
  networking.networkmanager = {
    enable = true;
    dispatcherScripts = [
      {
        source = pkgs.writeText "upHook" ''
          #!/usr/bin/env sh
          LOG_PREFIX="WiFi Auto-Toggle"
          ETHERNET_INTERFACE="eno2"

          if [ "$1" = "$ETHERNET_INTERFACE" ]; then
              case "$2" in
                  up)
                      echo "$LOG_PREFIX ethernet up"
                      nmcli radio wifi off
                      ;;
                  down)
                      echo "$LOG_PREFIX ethernet down"
                      nmcli radio wifi on
                      ;;
              esac
          elif [ "$(nmcli -g GENERAL.STATE device show $ETHERNET_INTERFACE)" = "20 (unavailable)" ]; then
              echo "$LOG_PREFIX failsafe"
              nmcli radio wifi on
            fi 
        '';
        type = "basic";
      }
    ];
  };
}

{ lib, pkgs, ... }:
{
  # Temporary watchdog: revert to gen 33 if WireGuard doesn't come up
  systemd.services.wg-boot-watchdog = {
    description = "Revert to gen 33 if WireGuard fails to connect after boot";
    after = [ "network-online.target" "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.wireguard-tools ];
    script = ''
      for i in $(seq 1 30); do
        if wg show wg-remote 2>/dev/null | grep -q "latest handshake"; then
          echo "WireGuard connected, all good"
          exit 0
        fi
        sleep 10
      done
      echo "WireGuard failed to connect in 5 minutes, reverting to gen 33"
      /nix/var/nix/gcroots/gen-33-backup/bin/switch-to-configuration boot
      reboot
    '';
  };

  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
  networking.firewall.checkReversePath = "loose";

  my.secrets.wireguard.pubkeys.enable = true;

  my.network.wg-remote = {
    enable = true;
    address = "10.50.50.5/32";
    autoconnect = "true";
    dns = "10.73.73.6";
    dnsPriority = 50;
    routeMetric = 50000;
    peer = {
      endpoint = "taylordnsfree.zapto.org:51820";
      allowedIPs = "10.73.73.0/24;10.50.0.0/16;";
    };
  };
}

{
  networking.firewall = {
    enable = true;

    # Public-facing (OCI VNIC). Deliberately no port 22 here: this mirrors the
    # old remote-nginx-nix posture where SSH was reachable only over the
    # tunnel. If wg-remote is ever down you recover via the OCI serial
    # console, not via public SSH.
    #
    # NOTE: the interface name is not pinned (OCI has used ens3/enp0s3/enp0s5
    # across shapes), so these are global rather than per-interface rules.
    allowedTCPPorts = [
      80
      443
      25565
    ];
    allowedUDPPorts = [ 27017 ];

    # Admin plane. The old config named this interface "remotewg", which never
    # matched anything: modules/network/networkmanager/wireguard/wg-remote.nix
    # creates the link as "wg-remote".
    interfaces."wg-remote" = {
      allowedTCPPorts = [
        22
        80
        443
        25565
      ];
      allowedUDPPorts = [ 27017 ];
    };
  };
}

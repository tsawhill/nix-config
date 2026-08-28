{ ... }:
{
  systemd.tmpfiles.rules = [
    "d /var/lib/pyload 0770 root download -"
  ];

  virtualisation.oci-containers = {
    backend = "docker";
    containers.pyload = {
      image = "lscr.io/linuxserver/pyload-ng:0.5.0b3.dev101-ls249";
      ports = [ "8000:8000" ];
      volumes = [
        "/var/lib/pyload:/config"
        "/mnt/downloadHDD:/downloads"
        "/mnt/downloadSSD:/downloads-ssd"
      ];
      environment = {
        PUID = "0";
        PGID = "1001";
        TZ = "America/Los_Angeles";
        UMASK = "002";
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 8000 ];
}

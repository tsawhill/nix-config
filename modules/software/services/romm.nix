{ pkgs, ... }:

{
  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings.ipv6 = false;
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {

      "romm-db" = {
        image = "mariadb:latest";
        extraOptions = [
          "--network=romm-network"
          "--user=0:1005"
        ];
        environment = {
          MARIADB_DATABASE = "romm";
          MARIADB_USER = "romm-user";
        };
        environmentFiles = [ "/root/.romm-env" ];
        volumes = [
          "mysql_data:/var/lib/mysql"
        ];
      };

      "romm" = {
        image = "rommapp/romm:latest";
        extraOptions = [
          "--network=romm-network"
          "--user=0:1005"
        ];
        dependsOn = [ "romm-db" ];
        environment = {
          DB_HOST = "romm-db";
          DB_NAME = "romm";
          DB_USER = "romm-user";
          LISTEN_IPV6 = "false";
        };
        environmentFiles = [ "/root/.romm-env" ];
        ports = [ "80:8080" ];
        volumes = [
          "romm_resources:/romm/resources"
          "romm_redis_data:/redis-data"
          "/mnt/zpool/roms:/romm/library/roms"
          "/mnt/zpool/gamesaves:/romm/assets"
          "/root/romm:/romm/config"
          "/root/romm/nginx.conf:/etc/nginx/conf.d/default.conf:ro"
        ];
      };
    };
  };
  # This ensures the network exists before the containers try to start
  systemd.services.init-romm-network = {
    description = "Create the Docker network for RomM.";
    after = [
      "network.target"
      "docker.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      check=$(${pkgs.docker}/bin/docker network ls -qf name=romm-network)
      if [ -z "$check" ]; then
        ${pkgs.docker}/bin/docker network create --ipv6=false romm-network
      fi
    '';
  };

  networking.firewall.allowedTCPPorts = [ 80 ];
}

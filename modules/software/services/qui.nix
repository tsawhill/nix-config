{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.qui;
in
{
  options.my.services.qui = {
    enable = lib.mkEnableOption "qui, a web UI over multiple qBittorrent instances";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7476;
      description = "Port qui listens on.";
    };

    metricsPort = lib.mkOption {
      type = lib.types.port;
      default = 9098;
      description = "Port for qui's Prometheus metrics endpoint.";
    };

    sessionSecret = lib.mkOption {
      type = lib.types.str;
      default = "qui_session_secret";
      description = ''
        SOPS secret holding qui's session secret. This encrypts the qBittorrent
        credentials in qui's database, so rotating it deregisters every instance.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.qui = {
      enable = true;
      openFirewall = true;
      secretFile = config.sops.secrets.${cfg.sessionSecret}.path;
      settings = {
        # nginx reaches this from local-nginx-nix, so it cannot bind loopback.
        host = "0.0.0.0";
        inherit (cfg) port;
        logLevel = "INFO";
        metricsEnabled = true;
        metricsHost = "0.0.0.0";
        metricsPort = cfg.metricsPort;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.metricsPort ];
  };
}

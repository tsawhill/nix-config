{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.flaresolverr;
in
{
  options.my.services.flaresolverr = {
    enable = lib.mkEnableOption "FlareSolverr, for indexers behind a Cloudflare managed challenge";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8191;
      description = "Port FlareSolverr listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Deliberately co-located with Prowlarr. Cloudflare binds clearance to the
    # User-Agent, and sharing a host means the solver and the consumer also share
    # an egress IP, so a mismatch cannot arise.
    #
    # The firewall is left closed: Prowlarr reaches it over loopback and nothing
    # else should. This runs a headless browser against untrusted tracker pages,
    # so upstream's DynamicUser and sandboxing are left exactly as they are.
    services.flaresolverr = {
      enable = true;
      inherit (cfg) port;
      openFirewall = false;
    };
  };
}

{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.byparr;
in
{
  options.my.services.byparr = {
    enable = lib.mkEnableOption "Byparr, for indexers behind a Cloudflare challenge";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8191;
      description = "Loopback port Byparr listens on. Prowlarr treats it as a FlareSolverr proxy.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/thephaseless/byparr@sha256:874f719518f617d03a60e03411fc5d090647e1a877041e81f8dc965927c7deb6";
      description = ''
        Pinned by digest: upstream publishes only latest/main/nightly, so there
        is no version tag to pin to. Byparr is not in nixpkgs, making this the
        one part of the stack not built from a pinned source tree — bump it
        deliberately by resolving a new digest, never by moving to a tag.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Byparr replaces FlareSolverr, whose patched Chromium current Cloudflare
    # detects and loops. Same /v1 API, so Prowlarr still configures it as a
    # FlareSolverr proxy.
    virtualisation.oci-containers = {
      backend = "docker";
      containers.byparr = {
        inherit (cfg) image;
        # Loopback only. Prowlarr runs on this host and nothing else should reach it.
        ports = [ "127.0.0.1:${toString cfg.port}:8191" ];
        # The browser needs more than Docker's default 64M of shared memory.
        extraOptions = [ "--shm-size=512m" ];
      };
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.byparr;

  # Byparr is not in nixpkgs, so the image is pulled into the Nix store as a
  # fixed-output derivation rather than fetched from a registry at service
  # start. That puts it in the system closure and removes the runtime network
  # dependency. Upstream publishes only latest/main/nightly, so the pin that
  # matters is imageDigest; finalImageTag is cosmetic. To bump: resolve a new
  # digest, then re-run nix-prefetch-docker for the hash.
  image = pkgs.dockerTools.pullImage {
    imageName = "ghcr.io/thephaseless/byparr";
    imageDigest = "sha256:874f719518f617d03a60e03411fc5d090647e1a877041e81f8dc965927c7deb6";
    hash = "sha256-1BXMKL3Uv66u041MjYSBBMbwLePeDpcLXrJihJSX/bE=";
    finalImageName = "ghcr.io/thephaseless/byparr";
    finalImageTag = "latest";
    arch = "amd64";
    os = "linux";
  };
in
{
  options.my.services.byparr = {
    enable = lib.mkEnableOption "Byparr, for indexers behind a Cloudflare challenge";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8191;
      description = "Loopback port Byparr listens on. Prowlarr treats it as a FlareSolverr proxy.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Byparr replaces FlareSolverr, whose patched Chromium current Cloudflare
    # detects and loops. Same /v1 API, so Prowlarr still configures it as a
    # FlareSolverr proxy.
    virtualisation.oci-containers = {
      backend = "docker";
      containers.byparr = {
        imageFile = image;
        # Must match finalImageName:finalImageTag above. The tag reads as
        # floating but nothing resolves it: the bytes come from imageFile.
        image = "ghcr.io/thephaseless/byparr:latest";
        # Loopback only. Prowlarr runs on this host and nothing else should reach it.
        ports = [ "127.0.0.1:${toString cfg.port}:8191" ];
        # The browser needs more than Docker's default 64M of shared memory.
        extraOptions = [ "--shm-size=512m" ];
      };
    };
  };
}

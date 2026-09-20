{
  inputs,
  config,
  pkgs,
  ...
}:
{
  imports = [ inputs.authentik-nix.nixosModules.default ];
  networking.firewall.allowedTCPPorts = [
    389
    636
    9000
  ];
  networking.firewall.allowedUDPPorts = [
    389
    636
  ];
  services.authentik = {
    enable = true;
    environmentFile = config.sops.secrets.authentik_env.path;

    settings = {
      cookie_domain = "tsawhill.org";
      authentik_host_browser = "https://auth.tsawhill.org";
      email = {
        host = "smtp.purelymail.com";
        port = 587;
        username = "authentik@tsawhill.org";
        use_tls = true;
        use_ssl = false;
        from = "authentik@tsawhill.org";
      };
      listen = {
        http = "0.0.0.0:9000";
        https = "0.0.0.0:9443";
        # metrics = "0.0.0.0:9300"; # Optional: if you need metrics exposed
      };
      disable_startup_analytics = true;
      avatars = "initials";
    };
  };
  # Enable OCI containers (Docker or Podman)
  virtualisation.oci-containers.backend = "docker"; # Or "podman"

  # Define the LDAP Outpost Container
  virtualisation.oci-containers.containers.authentik-ldap-outpost = {
    # Pulled into the Nix store rather than fetched at service start, so the
    # image is part of the closure. Pinned to 2026.5.6 to match the authentik
    # server: outposts track the server version, so bump both together.
    imageFile = pkgs.dockerTools.pullImage {
      imageName = "ghcr.io/goauthentik/ldap";
      imageDigest = "sha256:68a595f5a7b75fb3615f1609725adaf1d45f743aafece715d943b9706074c307";
      hash = "sha256-VVXWo+piQZb47YqeSBoI2zWxHNJE4C6VDKOGDc4bpz4=";
      finalImageName = "ghcr.io/goauthentik/ldap";
      finalImageTag = "2026.5.6";
      arch = "amd64";
      os = "linux";
    };
    image = "ghcr.io/goauthentik/ldap:2026.5.6";

    # Map the standard LDAP ports
    # Host Port : Container Port
    ports = [
      "389:3389"
      "636:6636"
    ];

    # Load the variables from your env file
    environmentFiles = [
      config.sops.secrets.authentik_ldap_outpost.path
    ];

    # Optional: If you need it on a specific docker network (e.g. to talk to Authentik)
    # extraOptions = [ "--network=authentik-network" ];
  };

}

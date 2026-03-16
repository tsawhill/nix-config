{ inputs, ... }:
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
    environmentFile = "/root/.authentik-env";

    settings = {
      cookie_domain = "tsawhill.org";
      authentik_host_browser = "https://auth.tsawhill.org";
      email = {
        host = "smtp.example.com";
        port = 587;
        username = "authentik@example.com";
        use_tls = true;
        use_ssl = false;
        from = "authentik@example.com";
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
  # 1. Enable OCI containers (Docker or Podman)
  virtualisation.oci-containers.backend = "docker"; # Or "podman"

  # 2. Define the LDAP Outpost Container
  virtualisation.oci-containers.containers.authentik-ldap-outpost = {
    image = "ghcr.io/goauthentik/ldap:latest"; # Or pin a version like :2024.2.1

    # Map the standard LDAP ports
    # Host Port : Container Port
    ports = [
      "389:3389"
      "636:6636"
    ];

    # Load the variables from your env file
    environmentFiles = [
      "/var/lib/authentik/ldap-outpost.env"
    ];

    # Optional: If you need it on a specific docker network (e.g. to talk to Authentik)
    # extraOptions = [ "--network=authentik-network" ];
  };

}

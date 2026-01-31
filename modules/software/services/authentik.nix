{ inputs, ... }:
{
  imports = [ inputs.authentik-nix.nixosModules.default ];
  services.authentik = {
    enable = true;
    environmentFile = "/root/.authentik-env";
    settings = {
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
  networking.firewall.allowedTCPPorts = [
    9000
  ];
}

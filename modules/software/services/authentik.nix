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
      disable_startup_analytics = true;
      avatars = "initials";
    };
  };
}

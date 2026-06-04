{ self, ... }:
{
  imports = [ "${self}/modules/software/services/syncthing" ];

  my.syncthing = {
    enable = true;
    device = "laptop";
    user = "taylor";
    group = "users";
    credentialsFile = "${self}/modules/secrets/syncthing/taylor-laptop-nix.yaml";
  };
}

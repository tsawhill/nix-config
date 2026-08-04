{ self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/palworld.nix"
  ];

  services.palworld = {
    enable = true;

    # nixos-factory initially provisions a 2 GiB RAM / 4 GiB disk LXC.
    # Keep the server stopped until the generated Incus entry is resized.
    autoStart = false;

    serverName = "Taylor's Palworld Server";
    serverDescription = "Palworld dedicated server";
    maxPlayers = 16;
  };

  networking.hostName = "palworld-nix";
}

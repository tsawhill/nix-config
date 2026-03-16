inputs@{ self, nixpkgs-stable, ... }:
{
  nixosConfigurations = {

    ##########################################################################
    #                          pi-backup-nix config                          #
    ##########################################################################
    pi-backup-nix = nixpkgs-stable.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [
        inputs.raspberry-pi-nix.nixosModules.raspberry-pi
        inputs.raspberry-pi-nix.nixosModules.sd-image
        "${self}/hosts/pi-backup-nix"
      ];
    };
  };
}

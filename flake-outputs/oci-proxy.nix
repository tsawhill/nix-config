inputs@{ self, nixpkgs-stable, ... }:
{
  nixosConfigurations = {

    ##########################################################################
    #                        remote-nginx-nix config                         #
    ##########################################################################
    remote-nginx-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        nixvim-input = inputs.nixvim-stable;
      };
      modules = [ "${self}/hosts/remote-nginx-nix" ];
    };
  };
}

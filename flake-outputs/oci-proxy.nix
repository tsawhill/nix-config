inputs@{ self, nixpkgs-stable, ... }:
let
  networkTopology = import "${self}/modules/network/topology.nix";

  ociSpecialArgs = {
    inherit inputs;
    inherit networkTopology;
    self = self;
    nixvim-input = inputs.nixvim-stable;
  };
in
{
  nixosConfigurations = {

    ##########################################################################
    #                        remote-nginx-nix config                         #
    ##########################################################################
    remote-nginx-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = ociSpecialArgs;
      modules = [ "${self}/hosts/remote-nginx-nix" ];
    };
  };
}

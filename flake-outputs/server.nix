inputs@{ self, nixpkgs-stable, ... }:
let
  networkTopology = import "${self}/modules/network/topology.nix";
in
{
  nixosConfigurations = {

    ##########################################################################
    #                            server-nix config                           #
    ##########################################################################
    server-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        inherit networkTopology;
        self = self;
        home-manager-input = inputs.home-manager-stable;
        nixvim-input = inputs.nixvim-stable;
        sops-input = inputs.sops-nix-stable;
        nix-vscode-extensions-input = inputs.nix-vscode-extensions-stable;
      };
      modules = [ "${self}/hosts/server-nix" ];
    };

    ##########################################################################
    #                             build-nix config                           #
    ##########################################################################
    build-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        inherit networkTopology;
        self = self;
        home-manager-input = inputs.home-manager-stable;
        nixvim-input = inputs.nixvim-stable;
        sops-input = inputs.sops-nix-stable;
        nix-vscode-extensions-input = inputs.nix-vscode-extensions-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/build.nix" ];
    };

  };
}

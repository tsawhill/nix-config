inputs@{ self, nixpkgs-stable, ... }:
{
  nixosConfigurations = {

    ##########################################################################
    #                            server-nix config                           #
    ##########################################################################
    server-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        home-manager-input = inputs.home-manager-stable;
        nixvim-input = inputs.nixvim-stable;
        sops-input = inputs.sops-nix-stable;
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
        self = self;
        home-manager-input = inputs.home-manager-stable;
        nixvim-input = inputs.nixvim-stable;
        sops-input = inputs.sops-nix-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/build.nix" ];
    };

    ##########################################################################
    #                            router-nix config                           #
    ##########################################################################
    router-nix = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        home-manager-input = inputs.home-manager-stable;
        nixvim-input = inputs.nixvim-stable;
        sops-input = inputs.sops-nix-stable;
      };
      modules = [ "${self}/hosts/server-nix/LXCs/router.nix" ];
    };

  };
}

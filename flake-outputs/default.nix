inputs@{ self, nixpkgs-unstable, ... }:
{
  nixosConfigurations = {
    ##########################################################################
    #                            desktop nix config                          #
    ##########################################################################
    desktop-nix = nixpkgs-unstable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        home-manager-input = inputs.home-manager-unstable;
        nixvim-input = inputs.nixvim-unstable;
        sops-input = inputs.sops-nix-unstable;
        zen-input = inputs.zen-browser-unstable;
      };
      modules = [ "${self}/hosts/desktop-nix" ];
    };
    ##########################################################################
    #                            laptop nix config                           #
    ##########################################################################
    laptop-nix = nixpkgs-unstable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        self = self;
        home-manager-input = inputs.home-manager-unstable;
        nixvim-input = inputs.nixvim-unstable;
        sops-input = inputs.sops-nix-unstable;
        zen-input = inputs.zen-browser-unstable;
      };
      modules = [ "${self}/hosts/laptop-nix" ];
    };
  };
}

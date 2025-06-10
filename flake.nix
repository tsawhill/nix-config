{
  description = "NixOS Configuration";

  outputs =
    {
      self,
      nixpkgs,
      downgradegamescope,
      chaotic,
      jovian,
      ...
    }@inputs:
    {
      nixosConfigurations.taylor-nix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          pkgs-gamescope = import downgradegamescope {
            system = "x86_64-linux";
          };
        };
        modules = [
          ./modules/shared
          ./modules/desktop
          { nixpkgs.overlays = [ inputs.hyprpanel.overlay ]; }
        ];
      };
      nixosConfigurations.taylor-deck = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          pkgs-gamescope = import downgradegamescope {
            system = "x86_64-linux";
          };
        };
        modules = [
          # jovian.nixosModules.default
          # chaotic.nixosModules.default
          ./modules/steamdeck
        ];
      };

      nixosConfigurations.taylor-nixlaptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          pkgs-gamescope = import downgradegamescope {
            system = "x86_64-linux";
          };
        };
        modules = [
          ./modules/shared
          ./modules/laptop
          { nixpkgs.overlays = [ inputs.hyprpanel.overlay ]; }
        ];
      };
    };
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    downgradegamescope.url = "github:NixOS/nixpkgs?rev=8fcb6f1c4948305af52d19f887b89011ee2c080d";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
    };
    hyprpanel = {
      url = "github:jas-singhfsu/hyprpanel?rev=3bcd3c4710fc025bbe403948f10c3922a8bf5193";
    };
    walker = {
      url = "github:abenz1267/walker";
    };
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    jovian.follows = "chaotic/jovian";
  };
}

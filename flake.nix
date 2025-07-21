{
  description = "NixOS Configuration";

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-master,
      downgradegamescope,
      downgradefloorp,
      chaotic,
      jovian,
      ...
    }@inputs:
    {
      nixosConfigurations.taylor-nix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          pkgs-master = import nixpkgs-master {
            system = "x86_64-linux";
          };
          pkgs-gamescope = import downgradegamescope {
            system = "x86_64-linux";
          };
          pkgs-floorp = import downgradefloorp {
            system = "x86_64-linux";
          };
        };
        modules = [
          ./modules/shared
          ./modules/desktop
          # { nixpkgs.overlays = [ inputs.hyprpanel.overlay ]; }
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
          jovian.nixosModules.default
          chaotic.nixosModules.default
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
          pkgs-floorp = import downgradefloorp {
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
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    downgradegamescope.url = "github:NixOS/nixpkgs?rev=d00c99a117ed3f1e6dc9db30382713d61b3a638e";
    downgradefloorp.url = "github:NixOS/nixpkgs?rev=16c2a2eb1772f3d7baa69fedae4fa2aad2d88fcd";
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
      url = "github:jas-singhfsu/hyprpanel";
    };
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    jovian.follows = "chaotic/jovian";
  };
}

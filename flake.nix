{
  description = "NixOS Configuration";

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-master,
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
          pkgs-floorp = import downgradefloorp {
            system = "x86_64-linux";
          };
        };
        modules = [
          chaotic.nixosModules.default
          ./modules/shared
          ./modules/desktop
        ];
      };
      nixosConfigurations.taylor-deck = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
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
          pkgs-floorp = import downgradefloorp {
            system = "x86_64-linux";
          };
        };
        modules = [
          ./modules/shared
          chaotic.nixosModules.default
          ./modules/laptop
          { nixpkgs.overlays = [ inputs.hyprpanel.overlay ]; }
        ];
      };
    };
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    downgradefloorp.url = "github:NixOS/nixpkgs?rev=6fb4fbce4f662f85e2aecd3ec8a00df5fb1224dc";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      # url = "github:sawb/Hyprland/hdr-sdr-no-scanout";
      url = "github:hyprwm/Hyprland";
    };
    hyprpanel = {
      url = "github:jas-singhfsu/hyprpanel";
    };
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    jovian.follows = "chaotic/jovian";
  };
}

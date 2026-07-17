{
  description = "NixOS Configuration";

  inputs = {
    authentik-nix.url = "github:nix-community/authentik-nix";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    elephant.url = "github:abenz1267/elephant";
    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };
    kopuz.url = "github:temidaradev/kopuz";

    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager-stable = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    # TEMP: remove once nixos-raspberrypi tracks nixos-26.05.
    # pi-backup-nix is built on nixos-raspberrypi's pinned nixos-25.11 nixpkgs,
    # but the fleet-standard 26.05 inputs assume nixpkgs 26.05 APIs and so can't
    # evaluate against the pi's 25.11 pkgs:
    #   - home-manager 26.05's modular-services imports `${pkgs.path}/lib/services/lib.nix`
    #   - nixvim 26.05 calls `pkgs.neovimUtils.makeVimPackageInfo`
    # neither exists in nixpkgs 25.11. Pin matching 25.11 home-manager + nixvim
    # for that one host as a bridge. When upstream nixos-raspberrypi moves to
    # nixos-26.05, delete these two inputs and revert
    # hosts/pi-backup-nix/home-manager.nix back to home-manager-stable / nixvim-stable.
    home-manager-2511.url = "github:nix-community/home-manager/release-25.11";
    nixvim-2511.url = "github:nix-community/nixvim/nixos-25.11";

    nixvim-stable = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    sops-nix-stable = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    zen-browser-stable = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    nix-vscode-extensions-stable = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    nixpkgs-master.url = "github:NixOS/nixpkgs/33d37b339dba37885ea13a77f01576af358791fb"; # pin: last working deploy 2026-04-07

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager-unstable = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nixvim-unstable = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    sops-nix-unstable = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    zen-browser-unstable = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-vscode-extensions-unstable = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    inputs:
    let
      # Load server outputs
      serverOutputs = import ./flake-outputs/server.nix inputs;
      piOutputs = import ./flake-outputs/pi-backup.nix inputs;
      # Load OCI server outputs
      ociOutputs = import ./flake-outputs/oci-proxy.nix inputs;
      # Colmena deployment hive
      colmenaOutputs = import ./flake-outputs/colmena.nix inputs;

      pkgs = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
      networkTopology = import ./modules/network/topology.nix;
    in
    colmenaOutputs
    // {
      nixosConfigurations =
        (serverOutputs.nixosConfigurations or { })
        // (piOutputs.nixosConfigurations or { })
        // (ociOutputs.nixosConfigurations or { })
        // {
          # Exposed so the Steam Deck can be first-installed with
          # `nixos-install --flake .#taylor-deck-nix`. Built with the same
          # unstable inputs colmena uses; day-to-day updates still go through
          # colmena (`deploy taylor-deck-nix`).
          taylor-deck-nix = inputs.nixpkgs-unstable.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              inherit inputs;
              inherit networkTopology;
              self = inputs.self;
              home-manager-input = inputs.home-manager-unstable;
              nixvim-input = inputs.nixvim-unstable;
              sops-input = inputs.sops-nix-unstable;
              zen-input = inputs.zen-browser-unstable;
              nix-vscode-extensions-input = inputs.nix-vscode-extensions-unstable;
            };
            modules = [ "${inputs.self}/hosts/taylor-deck-nix" ];
          };

          # Steam Machine ("cube"). Same unstable inputs colmena uses; day-to-day
          # updates go through colmena (`deploy taylor-cube-nix`).
          taylor-cube-nix = inputs.nixpkgs-unstable.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              inherit inputs;
              inherit networkTopology;
              self = inputs.self;
              home-manager-input = inputs.home-manager-unstable;
              nixvim-input = inputs.nixvim-unstable;
              sops-input = inputs.sops-nix-unstable;
              zen-input = inputs.zen-browser-unstable;
              nix-vscode-extensions-input = inputs.nix-vscode-extensions-unstable;
            };
            modules = [ "${inputs.self}/hosts/taylor-cube-nix" ];
          };
        };

      packages.x86_64-linux = {
        yarc-launcher = pkgs.callPackage ./pkgs/yarc-launcher.nix { };
        hyprcrosshair = pkgs.callPackage ./pkgs/hyprcrosshair/package.nix { };
        santroller-configurator = pkgs.callPackage ./pkgs/santroller-configurator/package.nix { };
        kopuz = inputs.kopuz.packages.x86_64-linux.default;
      };

      nixosModules = {
        router = import ./modules/router;
      };
    };
}

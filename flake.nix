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

    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager-stable = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    nixvim-stable = {
      url = "github:nix-community/nixvim/nixos-25.11";
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

    hyprland = {
      url = "github:hyprwm/Hyprland/202cf48ecf627839c0a7433cbeb018c744214390";
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
    in
    colmenaOutputs
    // {
      nixosConfigurations =
        (serverOutputs.nixosConfigurations or { })
        // (piOutputs.nixosConfigurations or { })
        // (ociOutputs.nixosConfigurations or { });

      packages.x86_64-linux.yarc-launcher = pkgs.callPackage ./pkgs/yarc-launcher.nix { };
      packages.x86_64-linux.hyprcrosshair = pkgs.callPackage ./pkgs/hyprcrosshair/package.nix { };
    };
}

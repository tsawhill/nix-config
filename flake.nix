{
  description = "NixOS Configuration";

  inputs = {
    authentik-nix.url = "github:nix-community/authentik-nix";
    raspberry-pi-nix.url = "github:nix-community/raspberry-pi-nix";

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
  };

  outputs =
    inputs:
    let
      # Load main outputs
      mainOutputs = import ./flake-outputs/default.nix inputs;
      # Load server outputs
      serverOutputs = import ./flake-outputs/server.nix inputs;
      piOutputs = import ./flake-outputs/pi-backup.nix inputs;
      # Load OCI server outputs
      ociOutputs = import ./flake-outputs/oci-proxy.nix inputs;
      # Colmena deployment hive (LXC hosts)
      colmenaOutputs = import ./flake-outputs/colmena.nix inputs;
    in
    # Merge them together. // merges the top level,
    # but we specifically need to merge the nixosConfigurations sets.
    mainOutputs
    // colmenaOutputs
    // {
      nixosConfigurations =
        (mainOutputs.nixosConfigurations or { })
        // (serverOutputs.nixosConfigurations or { })
        // (piOutputs.nixosConfigurations or { })
        // (ociOutputs.nixosConfigurations or { });
    };
}

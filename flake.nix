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
    in
    # Merge them together. // merges the top level,
    # but we specifically need to merge the nixosConfigurations sets.
    mainOutputs
    // {
      nixosConfigurations =
        (mainOutputs.nixosConfigurations or { })
        // (serverOutputs.nixosConfigurations or { })
        // (piOutputs.nixosConfigurations or { })
        // (ociOutputs.nixosConfigurations or { });
    };
}

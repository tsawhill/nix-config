{ inputs, self, ... }:
{
  imports = [
    # TEMP: using 25.11 home-manager (not home-manager-stable/26.05) because this
    # host builds on nixos-raspberrypi's pinned nixos-25.11 nixpkgs, and 26.05's
    # modular-services module needs lib/services/lib.nix which 25.11 nixpkgs lacks.
    # Revert to inputs.home-manager-stable when nixos-raspberrypi moves to 26.05.
    # See the home-manager-2511 input in flake.nix.
    inputs.home-manager-2511.nixosModules.default
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit inputs self;
      # TEMP: 25.11 nixvim for the same reason as home-manager-2511 above —
      # nixvim-stable (26.05) calls pkgs.neovimUtils.makeVimPackageInfo, absent
      # in this host's 25.11 pkgs. Revert to inputs.nixvim-stable when
      # nixos-raspberrypi moves to 26.05.
      nixvim-input = inputs.nixvim-2511;
    };

    users.root = {
      imports = [ "${self}/modules/home-manager/bundles/all.nix" ];
      home.stateVersion = "25.11";
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}

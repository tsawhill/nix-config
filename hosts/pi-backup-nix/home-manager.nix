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
    users.root = {
      # This host is an appliance, not an editing environment. Keep its SSH
      # shell small instead of pulling in Nixvim/Neovim, tree-sitter, Starship,
      # and their Rust-heavy ARM build closures.
      imports = [ "${self}/modules/home-manager/xdg.nix" ];

      programs.zsh = {
        enable = true;
        history = {
          size = 50000;
          save = 50000;
          share = true;
          ignoreDups = true;
          expireDuplicatesFirst = true;
          ignoreSpace = true;
        };
        shellAliases.g = "git";
      };

      home.stateVersion = "25.11";
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}

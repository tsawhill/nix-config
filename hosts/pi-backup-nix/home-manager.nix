{
  inputs,
  lib,
  self,
  ...
}:
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
    # Appliance, not an editing environment: the server shell bundle (Nu,
    # Starship) but no Nixvim/tree-sitter ARM build closures.
    users = lib.genAttrs [ "root" "taylor" ] (_: {
      imports = [ "${self}/modules/home-manager/bundles/server.nix" ];
      home.stateVersion = "25.11";
    });

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}

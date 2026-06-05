{
  inputs,
  self,
  home-manager-input,
  nixvim-input,
  ...
}:
{
  imports = [
    home-manager-input.nixosModules.default
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit
        inputs
        self
        home-manager-input
        nixvim-input
        ;
    };

    users.taylor = {
      # No Hyprland on the deck: import the shared CLI + GUI bundles only.
      # bundles/gui.nix brings games-frontends.nix (syncs the games library into
      # Steam as non-Steam shortcuts + Pegasus) and emulator-saves.nix.
      imports = [
        "${self}/modules/home-manager/bundles/all.nix"
        "${self}/modules/home-manager/bundles/gui.nix"
      ];
      home.stateVersion = "25.11";
      my.shell.starshipTheme = "personal";
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}

{
  config,
  inputs,
  lib,
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
      # No Hyprland here: import the shared CLI + GUI bundles only. bundles/gui.nix
      # brings games-frontends.nix (syncs the games library into Steam as
      # non-Steam shortcuts + Pegasus) and game save links.
      imports = [
        "${self}/modules/home-manager/bundles/all.nix"
        "${self}/modules/home-manager/bundles/gui.nix"
      ];
      home.stateVersion = "25.11";
      my.nixvim.full = true;
      my.shell.starshipTheme = "personal";

      # Steam starts immediately in Game Mode. Steam owns shortcuts.vdf while it is
      # running, so sync the declarative shortcuts in the same user-boot
      # transaction before Jovian's gamescope session starts.
      systemd.user.services.fetch-game-art = lib.mkIf (config.software.games.manifest != [ ]) {
        Unit.Before = [ "gamescope-session.service" ];
      };
      systemd.user.services.sync-steam-shortcuts = lib.mkIf (config.software.games.manifest != [ ]) {
        Unit = {
          Wants = [ "fetch-game-art.service" ];
          After = [ "fetch-game-art.service" ];
          Before = [ "gamescope-session.service" ];
        };
        Install.WantedBy = [ "default.target" ];
      };
    };

    backupFileExtension = "bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}

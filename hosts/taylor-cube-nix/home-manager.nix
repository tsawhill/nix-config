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
      # bundles/gui.nix brings games-frontends.nix (syncs the games library into
      # Steam as non-Steam shortcuts + Pegasus) and game save links.
      #
      # TEMPORARY (2026-07-31): the hypr stack, git config and hyprcrosshair are
      # here while the cube stands in as the primary workstation. Drop these
      # three imports (and the my.hypr/my.yarg block below) to return the cube to
      # a console-only box.
      imports = [
        "${self}/modules/home-manager/bundles/all.nix"
        "${self}/modules/home-manager/bundles/gui.nix"
        "${self}/modules/home-manager/git.nix"
        "${self}/modules/home-manager/gui/hypr"
        (import "${self}/pkgs/hyprcrosshair/hm-module.nix" self)
      ];
      home.stateVersion = "25.11";
      my.nixvim.full = true;
      my.shell.starshipTheme = "personal";
      my.yarg.enable = true;

      # Monitors are left unset on purpose: the cube drives a single display, and
      # monitors/fallback.nix (default-on) already configures HDMI-A-1 at highrr.
      # If `hyprctl monitors` reports a different output name after first boot,
      # set my.hypr.monitors.primary here.
      #
      # Deliberately NOT copied from taylor-desktop-nix:
      #   - AQ_DRM_DEVICES=/dev/dri/amd-dgpu — that symlink comes from the
      #     desktop's dGPU udev rules; the cube's APU has no such node.
      #   - my.hypr.gpuRecorder — left at its default (disabled).
      my.hypr.wallpaperEngine = {
        enable = true;
        # Requires Wallpaper Engine installed through Steam on this host (the
        # module reads ~/.steam/steam/steamapps/common/wallpaper_engine/assets).
        # Re-key this attr if the real output name is not HDMI-A-1.
        monitors."HDMI-A-1" = {
          wallpapers = [
            "3648098553"
            "3652040138"
            "3687714819"
          ];
          fps = 15;
          rotateInterval = "10m";
        };
      };

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

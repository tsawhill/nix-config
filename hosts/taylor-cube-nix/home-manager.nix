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
      # TEMPORARY (desktop rebuild): taylor-desktop-nix's Hyprland session moved
      # here, so the hypr dir, mangohud, vesktop settings and hyprcrosshair are
      # imported on top of the shared bundles. bundles/gui.nix still brings
      # games-frontends.nix (Steam non-Steam shortcuts + Pegasus) and game save
      # links. Revert with the rest of the stand-in commit.
      imports = [
        "${self}/modules/home-manager/bundles/all.nix"
        "${self}/modules/home-manager/bundles/gui.nix"
        "${self}/modules/home-manager/git.nix"
        "${self}/modules/home-manager/gui/hypr"
        "${self}/modules/home-manager/gui/mangohud.nix"
        "${self}/modules/home-manager/gui/vesktop.nix"
        (import "${self}/pkgs/hyprcrosshair/hm-module.nix" self)
      ];
      home.stateVersion = "26.05";
      my.nixvim.full = true;
      my.shell.starshipTheme = "personal";
      my.yarg.enable = true;

      my.hypr = {
        # The cube has exactly one DisplayPort and one HDMI, so the desktop's
        # DP-1/DP-2 pair becomes DP-1/HDMI-A-1: AW2725DF (360 Hz) on DP-1 as
        # primary, AW3423DWF (ultrawide) on HDMI-A-1. The per-monitor modes
        # themselves match on EDID (desc:...), so they follow the panels
        # regardless of port.
        monitors.primary = "DP-1";
        monitors.secondary = "HDMI-A-1";
        # monitors/fallback.nix matches the bare output name "HDMI-A-1" and
        # would shadow the AW3423DWF's HDR/10-bit desc: rule now that the
        # ultrawide is on HDMI. Both panels are described explicitly.
        monitors.fallback.enable = false;
        crosshair.monitor = "primary";
        gpuRecorder = {
          enable = true;
          captureTarget = "primary";
          videoCodec = "hevc_hdr";
          # quality = "ultra";
          extraArgs = [ "-tune quality" ];
          fps = 120;
          activation.processPatterns = [
            "gamescope"
            "net[.]runelite[.]client[.]RuneLite"
            "(^|/)cs2([[:space:]]|$)"
          ];
          audio.output = [
            "discord_audio.monitor"
            "game_audio.monitor"
            "desktop_audio.monitor"
          ];
          audio.input = [
            "mic_input"
            "alsa_input.usb-MOTU_M2_M2MA072BWT-00.pro-input-0"
          ];
        };
        wallpaperEngine = {
          enable = true;
          monitors."DP-1" = {
            wallpapers = [
              "3648098553"
              "3652040138"
              "3687714819"
            ];
            fps = 15;
            rotateInterval = "10m";
          };
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
      };

      # No AQ_DRM_DEVICES here: the desktop pins aquamarine to /dev/dri/amd-dgpu,
      # a symlink from its own iGPU/dGPU udev rules. The cube is single-GPU, so
      # there is nothing to disambiguate.

      # Kept from the Game Mode config so it still works if autoStart goes back
      # on: Steam owns shortcuts.vdf once Game Mode starts, so the declarative
      # shortcuts have to be synced before gamescope-session. Inert under the
      # Hyprland session, where Steam is not started at boot.
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

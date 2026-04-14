{ lib, config, ... }:
let
  cfg = config.my.desktop.audio.sinks;

  mkSink = name: description: {
    name = "libpipewire-module-loopback";
    args = {
      "node.description" = description;
      "capture.props" = {
        "node.name" = name;
        "media.class" = "Audio/Sink";
        "audio.position" = [
          "FL"
          "FR"
        ];
      };
      "playback.props" = {
        "node.name" = "${name}_out";
        "audio.position" = [
          "FL"
          "FR"
        ];
        "node.passive" = true;
      };
    };
  };

  mkRoute = matches: target: {
    inherit matches;
    actions.update-props."node.target" = target;
  };
in
{
  options.my.desktop.audio.sinks = {
    game.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable virtual Game Audio sink.";
    };
    music.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable virtual Music sink.";
    };
    discord.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable virtual Discord Audio sink.";
    };
    desktop.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable virtual Desktop Audio sink (catch-all).";
    };
  };

  config.services.pipewire = {

    # Virtual loopback sinks — enabled individually
    extraConfig.pipewire."93-virtual-sinks"."context.modules" =
      lib.optionals cfg.game.enable [ (mkSink "game_audio" "Game Audio") ]
      ++ lib.optionals cfg.music.enable [ (mkSink "music" "Music") ]
      ++ lib.optionals cfg.discord.enable [ (mkSink "discord_audio" "Discord Audio") ]
      ++ lib.optionals cfg.desktop.enable [ (mkSink "desktop_audio" "Desktop Audio") ];

    # Routing rules via pipewire-pulse (PulseAudio compat layer).
    # Rules are evaluated top-to-bottom; more specific matches override the catch-all.
    extraConfig.pipewire-pulse."94-app-routing"."stream.rules" =
      # Catch-all: send everything to Desktop Audio (must be first)
      lib.optionals cfg.desktop.enable [
        (mkRoute [ { "media.class" = "Stream/Output/Audio"; } ] "desktop_audio")
      ]
      # Discord (Electron)
      ++ lib.optionals cfg.discord.enable [
        (mkRoute [ { "application.process.binary" = "electron"; } ] "discord_audio")
      ]
      # mpv → Music
      ++ lib.optionals cfg.music.enable [
        (mkRoute [ { "application.process.binary" = "mpv"; } ] "music")
      ]
      # Games
      ++ lib.optionals cfg.game.enable [
        (mkRoute [
          { "application.name" = "deadlock.exe"; }
          { "application.process.binary" = "wine64-preloader"; }
        ] "game_audio")
        (mkRoute [
          { "application.name" = "ALSA plug-in [cs2]"; }
        ] "game_audio")
      ];

    # Give Vesktop/Electron nodes internal buffering so screenshare
    # capture doesn't cause xruns at low graph quantum.
    wireplumber.extraConfig."15-electron-buffer"."node.rules" = lib.mkIf cfg.discord.enable [
      {
        matches = [ { "application.process.binary" = "electron"; } ];
        actions.update-props."node.force-quantum" = 256;
      }
    ];
  };
}

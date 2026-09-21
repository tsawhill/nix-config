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
    matches = map (match: match // { "media.class" = "Stream/Output/Audio"; }) matches;
    actions.update-props."target.object" = target;
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

    # Run routing in the host session manager, including containerized native
    # clients that cannot load the host's PipeWire client.conf fragments.
    wireplumber.extraScripts."app-routing.lua" = builtins.readFile ./app-routing.lua;
    wireplumber.extraConfig."94-app-routing" = {
      "wireplumber.components" = [
        {
          name = "app-routing.lua";
          type = "script/lua";
          provides = "custom.app-routing";
        }
      ];
      "wireplumber.profiles".main."custom.app-routing" = "required";
    };

    # Rules are evaluated top-to-bottom; more specific matches override the catch-all.
    wireplumber.extraConfig."94-app-routing"."app-routing.rules" =
      # Catch-all: send everything to Desktop Audio (must be first)
      lib.optionals cfg.desktop.enable [
        (mkRoute [ { "media.class" = "Stream/Output/Audio"; } ] "desktop_audio")
      ]
      # Feishin also runs as electron, so match the application name instead.
      ++ lib.optionals cfg.discord.enable [
        (mkRoute [ { "application.name" = "~([Vv]esktop|[Dd]iscord).*"; } ] "discord_audio")
      ]
      # mpv → Music
      ++ lib.optionals cfg.music.enable [
        (mkRoute [
          { "application.process.binary" = "mpv"; }
          { "application.name" = "mpv"; }
          { "application.name" = "~[Ff]eishin.*"; }
        ] "music")
      ]
      # Games
      ++ lib.optionals cfg.game.enable [
        (mkRoute [
          { "application.name" = "deadlock.exe"; }
          { "application.process.binary" = "wine64-preloader"; }
          { "nix.game-audio" = "true"; }
        ] "game_audio")
        (mkRoute [
          { "application.name" = "ALSA plug-in [cs2]"; }
        ] "game_audio")
      ];

  };
}

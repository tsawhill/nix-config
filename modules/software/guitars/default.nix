{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.software.apps.gaming;
  profiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) (builtins.readDir ./.);
in
{
  imports = [
    ../packages/guitar-map.nix
  ]
  ++ map (name: ./. + "/${name}") (builtins.attrNames profiles);

  options.software.apps.gaming = {
    sdlGameControllerMappings = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SDL controller mappings contributed by guitar profiles and host modules.";
    };
    steamIgnoredGuitarDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "0x1209/0x2882" ];
      description = "Guitar VID/PID pairs hidden from the Steam client only.";
    };
  };

  config = lib.mkIf cfg.enable {
    software.guitarMap.enable = lib.mkDefault true;
    environment.sessionVariables = lib.optionalAttrs (cfg.sdlGameControllerMappings != [ ]) {
      SDL_GAMECONTROLLERCONFIG = lib.concatStringsSep "\n" cfg.sdlGameControllerMappings;
    };
    # mk-game-launcher removes this filter so launched games see the guitars.
    programs.steam.package = lib.mkIf (cfg.steamIgnoredGuitarDevices != [ ]) (
      pkgs.steam.override {
        extraEnv.SDL_GAMECONTROLLER_IGNORE_DEVICES = lib.concatStringsSep "," (
          lib.unique cfg.steamIgnoredGuitarDevices
        );
      }
    );
  };
}

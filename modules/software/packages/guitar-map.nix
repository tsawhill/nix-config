{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.software.guitarMap.enable = lib.mkEnableOption "interactive SDL guitar mapping tool";

  config = lib.mkIf config.software.guitarMap.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "guitar-map";
        text = ''
          export GUITAR_MAP_SDL_LIBRARY=${pkgs.SDL2}/lib/libSDL2.so
          exec ${pkgs.python3}/bin/python3 ${../../../pkgs/guitar-map/guitar_map.py} "$@"
        '';
      })
    ];
  };
}

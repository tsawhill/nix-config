{ lib, ... }:

let
  directoryContents = builtins.readDir ./.;

  gameModules = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) directoryContents;

  importPaths = map (name: ./. + "/${name}") (builtins.attrNames gameModules);
in
{
  imports = importPaths;

  options.software.games.exclude = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "guitarHero3" ];
    description = "Game launcher module ids to exclude from the default game library.";
  };

  options.software.games.gamescope.resolutions = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          width = lib.mkOption {
            type = lib.types.int;
            description = "Gamescope output and game width.";
          };

          height = lib.mkOption {
            type = lib.types.int;
            description = "Gamescope output and game height.";
          };
        };
      }
    );
    default = [ ];
    description = "Default gamescope resolutions to generate launchers for.";
  };
}

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
}

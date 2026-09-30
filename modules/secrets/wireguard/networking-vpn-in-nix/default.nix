{ lib, ... }:

let
  directoryContents = builtins.readDir ./.;

  nixFiles = lib.filterAttrs (
    name: type:
    (type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix") || (type == "directory")
  ) directoryContents;

  importPaths = map (name: ./. + "/${name}") (builtins.attrNames nixFiles);
in
{
  imports = importPaths;
}

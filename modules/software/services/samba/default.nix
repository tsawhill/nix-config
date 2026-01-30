{ lib, ... }:

let
  # Read the current directory
  directoryContents = builtins.readDir ./.;

  # Filter for:
  # 1. Files ending in .nix
  # 2. Files that are NOT 'default.nix'
  nixFiles = lib.filterAttrs (
    name: type:
    (type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix") || (type == "directory") # Also pick up folders
  ) directoryContents;

  # Convert the filenames into a list of absolute paths
  importPaths = map (name: ./. + "/${name}") (builtins.attrNames nixFiles);
in
{
  imports = importPaths;
}

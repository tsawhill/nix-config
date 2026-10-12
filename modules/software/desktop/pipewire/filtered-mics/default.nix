# One module per mic; each chain only runs while its device is plugged in.
{ lib, ... }:
let
  micFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) (builtins.readDir ./.);
in
{
  imports = map (name: ./. + "/${name}") (builtins.attrNames micFiles);
}

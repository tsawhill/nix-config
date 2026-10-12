# One module per mic; a chain only processes its own device and idles without it.
{ lib, ... }:
let
  micFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) (builtins.readDir ./.);
in
{
  imports = map (name: ./. + "/${name}") (builtins.attrNames micFiles);
}

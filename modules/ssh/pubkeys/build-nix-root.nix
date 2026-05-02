/*
  Function to allow SSH key access for a given list of users.

  Example usage:
  let
    sshUsers = ["root", "taylor"];
  in {
    imports = [ (import ./path/to/this/file.nix sshUsers) ];
  }
*/

targetUsers:
{ lib, ... }:
{
  users.users = lib.genAttrs targetUsers (name: {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMpZvx4kihRZV1pBxeHwsaIug7sgv7LSZrFl+P+of0fK root@build-nix"
    ];
  });
}

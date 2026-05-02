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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMBFsmNzZWYPyqHORl40pfN7RXrHlXFjN8EEmAhhlSIE taylor@nixos"
    ];
  });
}

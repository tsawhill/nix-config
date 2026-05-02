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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEBuWNRHGJ8nkDa+8IxEY7E7w1Maq3+6HbquWXELBVR0 factory@server-nix"
    ];
  });
}

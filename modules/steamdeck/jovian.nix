#
# jovian.nix -- Gaming
#
{ pkgs, ... }:
let
  # Local user account for auto login
  # Separate and distinct from Steam login
  # Can be any name you like
  gameuser = "taylor";
  jovian-nixos = builtins.fetchGit {
    url = "https://github.com/Jovian-Experiments/Jovian-NixOS";
    ref = "development";
  };
in
{
  system.activationScripts = {
    print-jovian = {
      text = builtins.trace "building the jovian configuration..." "";
    };
  };

  #
  # Imports
  #
  imports = [ "${jovian-nixos}/modules" ];

  #
  # Jovian
  #
  jovian.hardware.has.amd.gpu = true;

  jovian.steam.enable = true;

  #
  # SDDM
  #
  services.displayManager.sddm.settings = {
    Autologin = {
      Session = "gamescope-wayland.desktop";
      User = "taylor";
    };
  };

  programs.steam = {
    enable = true;
    localNetworkGameTransfers.openFirewall = true;
  };
}

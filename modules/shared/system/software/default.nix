{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;
  imports = [
    ./shell
    ./desktop
    ./gaming.nix
    ./gamescope.nix
    ./development-tools.nix
    ./configuration-tools.nix
    ./shell-utilities.nix
    ./desktop-apps.nix
  ];

  environment.systemPackages = with pkgs; [
    neovim

    wireguard-tools

    # Drivers for amd gpu
    mesa
    mesa-demos

    wine
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.geist-mono
    nerd-fonts.fira-code
    nerd-fonts.sauce-code-pro
    nerd-fonts.departure-mono
    nerd-fonts.daddy-time-mono
    nerd-fonts.victor-mono
  ];
}

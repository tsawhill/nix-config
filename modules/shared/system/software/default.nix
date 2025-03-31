{
  pkgs,
  ...
}:
{
  nixpkgs.config.allowUnfree = true;
  imports = [
    ./shell
    ./desktop
    ./gaming.nix
    ./development-tools.nix
    ./configuration-tools.nix
    ./shell-utilities.nix
    ./desktop-apps.nix
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  environment.systemPackages = with pkgs; [
    neovim

    # Drivers for amd gpu
    mesa
    mesa-demos

    wine
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.geist-mono
  ];
}

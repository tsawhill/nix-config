{
  pkgs,
  ...
}:
{
  programs.mtr.enable = true;
  environment.systemPackages = with pkgs; [
    sshfs
    tmux
    curl
    wget
    tree
    hyfetch
    nix-search
    nixos-rebuild-ng

    # Archive tools
    p7zip
    unar

    # Resource Management
    htop
    # nvtopPackages.full

    # Multimedia
    ffmpeg
  ];
}

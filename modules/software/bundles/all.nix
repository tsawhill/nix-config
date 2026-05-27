{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.software.all.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable core CLI and system tools.";
  };

  config = lib.mkIf config.software.all.enable {
    software.lan-launch.enable = true;
    # AppImage support
    programs.appimage = {
      enable = true;
      binfmt = true;
    };

    programs.mtr.enable = true;
    programs.zsh.enable = true;

    environment.systemPackages = with pkgs; [
      # System
      linux-firmware
      wireguard-tools
      mesa
      mesa-demos

      # File tools
      rsync
      file
      p7zip
      unar
      unrar
      unzip
      sshfs
      lsof

      # Network tools
      dnsutils
      iputils
      mtr
      nmap
      socat
      curl
      wget

      # Monitoring
      htop
      nvtopPackages.amd

      # Editors / shell
      neovim
      tmux
      tree
      hyfetch
      nix-search
      nixos-rebuild-ng

      # Multimedia CLI
      ffmpeg

      # Dev
      colmena
      git
      gotify-cli
    ];
  };
}

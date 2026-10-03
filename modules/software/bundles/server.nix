{
  config,
  lib,
  pkgs,
  self,
  ...
}:
{
  imports = [
    "${self}/modules/software/packages/ssh-copy.nix"
    ../packages/glow.nix
  ];

  options.software.server.enable = lib.mkEnableOption "headless server CLI tools";

  config = lib.mkIf config.software.server.enable {
    software.ssh-copy.enable = true;
    software.glow.enable = lib.mkDefault true;

    # No linux-firmware here: the kernel only loads firmware from hardware.firmware.
    environment.systemPackages = with pkgs; [
      # Core administration and troubleshooting.
      curl
      dnsutils
      file
      htop
      iputils
      lsof
      rsync
      tmux
      tree
      unzip
      wireguard-tools
    ];
  };
}

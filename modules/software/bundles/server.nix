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
  ];

  options.software.server.enable = lib.mkEnableOption "headless server CLI tools";

  config = lib.mkIf config.software.server.enable {
    software.ssh-copy.enable = true;
    programs.zsh.enable = true;

    environment.systemPackages =
      with pkgs;
      [
        # Core administration and troubleshooting.
        curl
        dnsutils
        file
        git
        htop
        iputils
        lsof
        neovim
        rsync
        tmux
        tree
        unzip
        wireguard-tools
      ]
      # Containers share their host's kernel and cannot load firmware.
      ++ lib.optionals (!config.boot.isContainer) [ linux-firmware ];
  };
}

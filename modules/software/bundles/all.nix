{
  pkgs,
  lib,
  config,
  self,
  inputs,
  ...
}:
{
  imports = [
    ./server.nix
    "${self}/modules/software/packages/lan-launch.nix"
  ];
  options.software.all.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable the complete CLI and workstation tool bundle.";
  };

  config = lib.mkIf config.software.all.enable {
    software.server.enable = true;
    software.lan-launch.enable = true;
    # AppImage support
    programs.appimage = {
      enable = true;
      binfmt = true;
    };

    programs.mtr.enable = true;
    environment.systemPackages = with pkgs; [
      # Extended file tools
      p7zip
      unar
      unrar
      sshfs

      # Extended network tools
      mtr
      nmap
      socat
      wget

      # GPU monitoring
      nvtopPackages.amd

      # Workstation shell conveniences
      hyfetch
      nix-search
      nixos-rebuild-ng

      # Multimedia CLI
      ffmpeg

      # Deployment tools; the CLI must match the flake's colmenaHive schema
      inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
      gotify-cli
    ];
  };
}

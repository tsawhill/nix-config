{ config, ... }:
{
  programs.git = {
    enable = true;
    package = null;

    settings = {
      user = {
        name = "Taylor Sawhill";
        email = "git@tsawhill.org";
      };

      safe.directory = [
        "/home/taylor/localmount/nixos-lxc-configs"
        "localmount/nixos-configs"
        "/home/taylor/localmount/nixos-configs"
        "/mnt/config2"
      ];
    };

    ignores = [ "**/.claude/settings.local.json" ];
  };

  # Git reads both the XDG config and ~/.gitconfig when both exist. Own the
  # legacy path too so it cannot silently override the declarative settings.
  home.file.".gitconfig".text = ''
    # Git configuration is managed by Home Manager in ${config.xdg.configHome}/git/config.
  '';
}

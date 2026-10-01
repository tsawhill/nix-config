{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Same config the workstations get through HM, minus HM.
  nuConfig = pkgs.writeText "00-config.nu" (
    builtins.readFile ../../home-manager/nushell-config.nu
    + ''
      $env.config.color_config.header = { fg: '#e0af68' attr: 'b' }
    ''
  );

  # Nushell sources share/nushell/vendor/autoload/*.nu from XDG_DATA_DIRS.
  nuAutoload = pkgs.runCommand "nushell-headless-autoload" { } ''
    dir=$out/share/nushell/vendor/autoload
    mkdir -p $dir
    cp ${nuConfig} $dir/00-config.nu
    HOME=$TMPDIR ${lib.getExe pkgs.starship} init nu > $dir/starship.nu
  '';

  starshipConfig = (pkgs.formats.toml { }).generate "starship.toml" (
    import ../../home-manager/starship-settings.nix true
  );
in
{
  imports = [ ./server.nix ];

  options.software.headless.enable = lib.mkEnableOption "slim server profile with Nushell over a bash login shell";

  config = lib.mkIf config.software.headless.enable {
    software.server.enable = true;

    # Plain priority also beats lxc-instance-common's mkOverride 890.
    documentation.enable = false;
    documentation.nixos.enable = false;
    documentation.man.enable = false;

    # Drops nixos-rebuild (python) and nixos-option (man-db); colmena pushes closures.
    system.disableInstallerTools = true;
    # deployctl reads it over SSH for deploy summaries.
    system.tools.nixos-version.enable = true;

    environment.systemPackages = [
      pkgs.nushell
      nuAutoload
    ];
    environment.pathsToLink = [ "/share/nushell" ];
    environment.etc."starship.toml".source = starshipConfig;
    environment.variables.STARSHIP_CONFIG = "/etc/starship.toml";

    # bash stays the login shell so ssh commands, colmena and scp see POSIX.
    my.users.root.shell = lib.mkDefault pkgs.bashInteractive;
    my.users.taylor.shell = lib.mkDefault pkgs.bashInteractive;
    # BASH_ONLY=1 bash is the escape hatch.
    programs.bash.interactiveShellInit = ''
      if [[ -z "$BASH_EXECUTION_STRING" && -z "$IN_NIX_SHELL" && -z "$BASH_ONLY" ]]; then
        exec ${lib.getExe pkgs.nushell}
      fi
    '';

    # Drop what Home Manager left behind: config links Nu would source after
    # GC, and the GC roots / HM-only nix-env profiles that pin old closures.
    system.activationScripts.headlessHmLeftovers = ''
      for f in /root/.config/nushell/config.nu /root/.config/nushell/env.nu /root/.config/starship.toml \
               /home/taylor/.config/nushell/config.nu /home/taylor/.config/nushell/env.nu /home/taylor/.config/starship.toml \
               /root/.local/state/home-manager/gcroots/current-home /home/taylor/.local/state/home-manager/gcroots/current-home; do
        if [ -L "$f" ]; then rm -f "$f"; fi
      done
      for dir in /root/.local/state/nix/profiles /nix/var/nix/profiles/per-user/root \
                 /home/taylor/.local/state/nix/profiles /nix/var/nix/profiles/per-user/taylor; do
        m="$dir/profile/manifest.nix"
        if [ -f "$m" ] && [ "$(grep -oE 'name = "[^"]+"' "$m" | sort -u)" = 'name = "home-manager-path"' ]; then
          rm -f "$dir"/profile "$dir"/profile-*-link
        fi
      done
      for l in /root/.nix-profile /home/taylor/.nix-profile; do
        if [ -L "$l" ] && [ ! -e "$l" ]; then rm -f "$l"; fi
      done
    '';
  };
}

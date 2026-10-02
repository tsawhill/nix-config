{
  config,
  lib,
  pkgs,
  ...
}:
let
  server = config.my.shell.starshipTheme == "server";
in
{
  imports = [ ./starship.nix ];

  # Used by the external completer in nushell-config.nu.
  home.packages = [ pkgs.carapace ];

  programs.nushell = {
    enable = true;
    shellAliases = {
      vim = "nvim";
      g = "git";
    }
    // lib.optionalAttrs (!server) {
      deploy = "ssh build-nix.lan deploy";
    };
    extraConfig = builtins.readFile ./nushell-config.nu + ''
      $env.config.color_config.header = { fg: '${if server then "#e0af68" else "#7aa2f7"}' attr: 'b' }
    '';
  };

  # bash stays the login shell so ssh commands, colmena and scp see POSIX;
  # interactive sessions hop into Nu from ~/.bashrc, after HM session vars load.
  # BASH_ONLY=1 bash is the escape hatch.
  programs.bash = {
    enable = true;
    initExtra = ''
      if [[ -z "$BASH_EXECUTION_STRING" && -z "$IN_NIX_SHELL" && -z "$BASH_ONLY" ]]; then
        exec ${lib.getExe pkgs.nushell}
      fi
    '';
  };
}

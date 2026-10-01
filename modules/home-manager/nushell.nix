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

  # Keep the POSIX-style login environment and SSH command handling used by
  # NixOS and deployment tools; Nu is the default for interactive sessions.
  # Run before completion/plugin setup. ZSH_ONLY=1 zsh is an escape hatch.
  programs.zsh.initContent = lib.mkOrder 100 ''
    if [[ -o interactive && -z "$ZSH_EXECUTION_STRING" && -z "$ZSH_ONLY" ]]; then
      exec ${lib.getExe pkgs.nushell}
    fi
  '';
}

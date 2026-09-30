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
    extraConfig = ''
      $env.config.show_banner = false
      $env.config.edit_mode = 'emacs'
      $env.config.table.mode = 'rounded'
      $env.config.history.file_format = 'sqlite'
      $env.config.history.max_size = 50000
      $env.config.history.isolation = false
      $env.config.color_config = ($env.config.color_config | merge {
        separator: '#414868'
        leading_trailing_space_bg: { attr: 'n' }
        header: { fg: '${if server then "#e0af68" else "#7aa2f7"}' attr: 'b' }
        row_index: '#bb9af7'
        string: '#9ece6a'
        int: '#ff9e64'
        float: '#ff9e64'
        bool: '#bb9af7'
        filesize: '#7dcfff'
        date: '#2ac3de'
        nothing: '#565f89'
        shape_internalcall: { fg: '#7aa2f7' attr: 'b' }
        shape_external: '#7dcfff'
        shape_string: '#9ece6a'
        shape_flag: '#bb9af7'
        shape_pipe: '#ff9e64'
        shape_variable: '#c0caf5'
      })
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

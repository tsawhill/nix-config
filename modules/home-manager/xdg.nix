{
  config,
  options,
  lib,
  ...
}:
{
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      extraConfig = {
        SCREENSHOTS = "${config.home.homeDirectory}/Pictures/Screenshots";
      };
    }
    # Default flipped to false at home.stateVersion 26.05; keep exporting
    # XDG_DESKTOP_DIR & friends. Guarded because pi-backup-nix is pinned to
    # home-manager 25.11, which predates the option.
    // lib.optionalAttrs (options.xdg.userDirs ? setSessionVariables) {
      setSessionVariables = true;
    };
  };
}

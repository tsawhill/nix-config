{
  imports = [
    ../nushell.nix
    ../xdg.nix
  ];

  # Rendering every HM option into a manpage is a large per-host eval cost.
  manual.manpages.enable = false;
}

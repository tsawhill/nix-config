{ lib, pkgs, ... }:
let
  types = [
    "text/html"
    "application/xhtml+xml"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/about"
    "x-scheme-handler/unknown"
  ];
in
{
  # Set per-activation instead of xdg.mimeApps so apps can still register handlers.
  home.activation.defaultBrowser = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.xdg-utils}/bin/xdg-mime default zen.desktop ${lib.concatStringsSep " " types}
  '';
  home.sessionVariables.BROWSER = "zen";
}

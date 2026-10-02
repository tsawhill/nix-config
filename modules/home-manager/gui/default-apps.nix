{ lib, pkgs, ... }:
let
  defaults = {
    "zen.desktop" = [
      "text/html"
      "application/xhtml+xml"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
    ];
    "nemo.desktop" = [ "inode/directory" ];
    "imv.desktop" = map (t: "image/${t}") [
      "png"
      "jpeg"
      "gif"
      "webp"
      "bmp"
      "tiff"
      "svg+xml"
      "avif"
      "heif"
      "jxl"
    ];
    "mpv.desktop" =
      map (t: "video/${t}") [
        "mp4"
        "x-matroska"
        "webm"
        "quicktime"
        "x-msvideo"
        "mpeg"
        "ogg"
        "x-flv"
        "3gpp"
      ]
      ++ map (t: "audio/${t}") [
        "mpeg"
        "flac"
        "ogg"
        "opus"
        "wav"
        "x-wav"
        "aac"
        "mp4"
        "x-m4a"
        "x-matroska"
      ];
    "nvim-foot.desktop" = [
      "text/plain"
      "text/markdown"
      "text/x-log"
      "text/csv"
      "text/x-python"
      "text/x-shellscript"
      "application/x-shellscript"
      "application/json"
      "application/toml"
      "application/x-yaml"
      "application/xml"
      "text/x-nix"
    ];
    "org.pwmt.zathura-pdf-mupdf.desktop" = [ "application/pdf" ];
  };
in
{
  home.packages = [
    pkgs.imv
    pkgs.zathura
  ];

  # nvim.desktop is Terminal=true, which xdg-open can't launch outside a DE.
  xdg.desktopEntries.nvim-foot = {
    name = "Neovim (foot)";
    exec = "foot nvim %F";
    mimeType = defaults."nvim-foot.desktop";
    noDisplay = true;
  };

  # Set per-activation instead of xdg.mimeApps so apps can still register handlers.
  home.activation.defaultApps = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    lib.concatStrings (
      lib.mapAttrsToList (app: types: ''
        run ${pkgs.xdg-utils}/bin/xdg-mime default ${app} ${lib.concatStringsSep " " types}
      '') defaults
    )
  );
  home.sessionVariables.BROWSER = "zen";
}

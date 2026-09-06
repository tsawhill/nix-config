{
  pkgs,
  lib,
  config,
  inputs,
  zen-input,
  ...
}:
let
  zenPackages = zen-input.packages.${pkgs.stdenv.hostPlatform.system};
  zenBrowser = zenPackages.default.override {
    zen-browser-unwrapped = zenPackages.zen-browser-unwrapped.overrideAttrs (old: {
      # The pinned Zen flake still uses ffmpegSupport; current wrapFirefox
      # checks withFFmpeg before adding the H.264/AAC runtime libraries.
      passthru = (old.passthru or { }) // {
        withFFmpeg = true;
      };
    });
  };
in
{
  options.software.apps.web.enable = lib.mkEnableOption "web browsers and related tools";

  config = lib.mkIf config.software.apps.web.enable {
    environment.systemPackages = with pkgs; [
      zenBrowser
      ungoogled-chromium
    ];
  };
}

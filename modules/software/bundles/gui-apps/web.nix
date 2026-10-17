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
  # The flake still sets ffmpegSupport; current wrapFirefox checks withFFmpeg
  # before adding the H.264/AAC runtime libraries.
  zenUnwrapped = zenPackages.beta-unwrapped.overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      withFFmpeg = true;
    };
  });
  # Same as the flake's wrap-zen.nix: wrapFirefox picks ffmpeg by Gecko version, not Zen's.
  zenBrowser =
    pkgs.wrapFirefox (zenUnwrapped // { version = zenUnwrapped.firefoxVersion or "9999"; })
      {
        inherit (zenUnwrapped) version;
        icon = "zen-browser";
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

{ lib, ... }:
let
  # HDR passthrough: gpu-next is the only vo that speaks wp-color-management-v1.
  hdrConfig = {
    vo = "gpu-next";
    gpu-api = "vulkan";
    target-colorspace-hint = "yes";
    hwdec = "auto-safe";
  };
in
{
  programs.mpv = {
    enable = true;
    config = hdrConfig;
  };

  # jellyfin-mpv-shim includes its own config instead of reading ~/.config/mpv.
  xdg.configFile."jellyfin-mpv-shim/mpv.conf".text = lib.generators.toKeyValue { } hdrConfig;

  # Jellium also uses an application-specific mpv home directory.
  xdg.configFile."jellyfin-desktop/mpv/mpv.conf".text = lib.generators.toKeyValue { } hdrConfig;
}

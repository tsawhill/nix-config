{ lib, ... }:
{
  # wayland.windowManager.hyprland.settings.monitor = [
  #   "DP-1,3440x1440@165,0x0,1,vrr,2"
  #   "DP-2,2560x1440@165,3440x0,1"
  #   "HDMI-A-1,3840x2160@60,0x0,1"
  #   "HEADLESS-1, 3840x2160@60, -3840x0, 1"
  # ];
  wayland.windowManager.hyprland.extraConfig = ''
    monitorv2 {
      output=desc:Dell Inc. AW2725DF CJ56ZZ3
      mode=2560x1440@360Hz
      position=auto
      scale=1
      vrr=1
      bitdepth=10
      supports_hdr=true
      sdr_min_luminance=0.005
      sdr_max_luminance=250
      supports_wide_color=true
    }
    monitorv2 {
      output=desc:Dell Inc. AW3423DWF 3D442S3
      mode=modeline 644.16  3440 3448 3480 3520  1440 1511 1519 1525 +hsync -vsync
      position=auto-right
      scale=1
      vrr=1
    }
    monitorv2 {
      output=desc:Dell Inc. DELL S2721DGF 98T9623
      mode=2560x1440@60.00Hz
      position=auto-right
      scale=1
      vrr=1
    }
    monitorv2 {
      output=HDMI-A-1
      mode=3840x2160@60
      position=auto
      scale=1
    }
    monitorv2 {
      output=HEADLESS-2
      mode=3840x2160@60
      position=0x10000
      scale=1
    }
    workspace = 11,monitor:HEADLESS-2,default:true
    exec=hyprctl output create headless HEADLESS-2
  '';
  # wayland.windowManager.hyprland.settings.monitorv2 = [
  #   {
  #     output = "DP-1";
  #     mode = "3440x1440@165";
  #     position = "0x0";
  #     scale = 1;
  #     vrr = 2;
  #   }
  #   {
  #     output = "DP-2";
  #     mode = "2560x1440@165";
  #     position = "3440x0";
  #     scale = 1;
  #   }
  #   {
  #     output = "HDMI-A-1";
  #     mode = "3840x2160@60";
  #     position = "0x0";
  #     scale = 1;
  #   }
  #   {
  #     output = "HEADLESS-1";
  #     mode = "3840x2160@60";
  #     position = "-3840x0";
  #     scale = 1;
  #   }

  #   ];
}

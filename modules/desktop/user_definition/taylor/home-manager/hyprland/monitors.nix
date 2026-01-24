{ lib, ... }:
{
  # wayland.windowManager.hyprland.settings.monitor = [
  #   "DP-1,3440x1440@165,0x0,1,vrr,2"
  #   "DP-2,2560x1440@165,3440x0,1"
  #   "HDMI-A-1,3840x2160@60,0x0,1"
  #   "HEADLESS-1, 3840x2160@60, -3840x0, 1"
  # ];
  wayland.windowManager.hyprland.settings.env = [
    "DRI_PRIME,  pci-0000_03_00_0"
    "AQ_DRM_DEVICES, /dev/dri/amd-dgpu:/dev/dri/amd-igpu"
  ];
  wayland.windowManager.hyprland.extraConfig = ''
    monitorv2 {
      output=desc:Dell Inc. AW2725DF CJ56ZZ3
      mode=2560x1440@360Hz
      position=0x0
      scale=1
      bitdepth=10
      supports_hdr=true
      cm=hdredid
      sdr_min_luminance = 0.005
      sdr_max_luminance = 240
      min_luminance = 0
      max_luminance = 400
      max_avg_luminance = 300
      supports_wide_color = true
    }
    monitorv2 {
      output=desc:Dell Inc. AW3423DWF 3D442S3
      mode=3440x1440@165Hz
      position=auto-right
      scale=1
      bitdepth=10
      supports_hdr=true
      cm=hdredid
      sdrbrightness=1
      sdrsaturation=1
      sdr_min_luminance = 0.005
      sdr_max_luminance = 150
      min_luminance = 0
      max_luminance = 400
      max_avg_luminance = 300
      supports_wide_color = true
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
    # exec=hyprctl output create headless HEADLESS-2
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

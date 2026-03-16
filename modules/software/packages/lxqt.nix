{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    labwc # The Compositor
    lxqt.lxqt-panel # The Taskbar
    lxqt.pcmanfm-qt # The Desktop/Wallpaper
    lxqt.lxqt-runner # Application launcher (Alt+F2)
    lxqt.lxqt-session
    wlr-randr # Display configuration tool
  ];
}

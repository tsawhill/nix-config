{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    networkmanagerapplet
    easyeffects
    pavucontrol
    openrgb

    #GTK configuration tools
    nwg-look
    dconf-editor
  ];
}
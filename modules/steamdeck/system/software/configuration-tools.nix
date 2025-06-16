{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    networkmanagerapplet
    easyeffects
    pavucontrol

    #GTK configuration tools
    nwg-look
    dconf-editor
  ];
}

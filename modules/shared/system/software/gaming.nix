{
  inputs,
  pkgs,
  ...
}:
let
  myUdevRule = pkgs.writeTextFile {
    name = "yarg-udev";
    text = ''
      KERNEL=="hidraw*", TAG+="uaccess"
    '';
    destination = "/etc/udev/rules.d/69-hid.rules"; # The destination path within the generated package
  };
in
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  programs.gpu-screen-recorder = {
    enable = true;
  };

  services.udev.packages = [ myUdevRule ];

  environment.systemPackages = with pkgs; [
    vulkan-headers
    gamemode
    mangohud
    gpu-screen-recorder
    heroic
    lutris
    protonplus
    # retroarch
    bolt-launcher
    gtk2
    gtk2-x11
    boilr
    moonlight-qt
    # rpcs3
    pcsx2
    yarg
  ];
}

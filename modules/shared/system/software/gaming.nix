{
  inputs,
  pkgs,
  ...
}:
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

  environment.systemPackages = with pkgs; [
    vulkan-headers
    gamemode
    mangohud
    gpu-screen-recorder
    heroic
    lutris
    protonplus
    retroarch
    # bolt-launcher
    boilr
    moonlight-qt
    rpcs3
    pcsx2
    yarg
  ];
}

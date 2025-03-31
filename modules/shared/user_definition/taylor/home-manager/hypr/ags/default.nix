{
  programs.ags = {
    enable = true;
    extraPackages = with pkgs; [
      inputs.ags.packages.${system}.hyprland
      inputs.ags.packages.${system}.wireplumber
      inputs.ags.packages.${system}.battery
      inputs.ags.packages.${system}.bluetooth
      inputs.ags.packages.${system}.network
      inputs.ags.packages.${system}.notifd
      inputs.ags.packages.${system}.apps
      inputs.ags.packages.${system}.mpris
      inputs.ags.packages.${system}.powerprofiles
    ];
  };
}

{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    vscodium
    nixfmt-classic
    git
    glib
  ];
}

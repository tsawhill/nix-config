{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    vscodium
    nixfmt-tree
    git
    glib
  ];
}

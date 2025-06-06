{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    vscodium
    nixfmt-rfc-style
    git
    glib
  ];
}

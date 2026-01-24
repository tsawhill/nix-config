{
  pkgs,
  ...
}:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    extensions = with pkgs.vscode-extensions; [
      # Extensions available in nixpkgs
      continue.continue
      jnoortheen.nix-ide
      esbenp.prettier-vscode
      ms-python.vscode-pylance
    ];
  };
  environment.systemPackages = with pkgs; [
    nixfmt-rfc-style
    git
    glib
  ];
}

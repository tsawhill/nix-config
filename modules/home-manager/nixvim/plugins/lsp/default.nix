{
  imports = [
    ./python.nix
    ./nix.nix
    ./lua.nix
    ./markdown.nix
    ./bash.nix
    ./json.nix
  ];
  programs.nixvim.plugins = {
    lsp-format = {
      enable = true;
    };
    lsp = {
      enable = true;
    };
  };
}

{ config, lib, ... }:
{
  imports = [
    ./telescope.nix
    ./commentary.nix
    ./which-key.nix
    ./web-devicons.nix
  ]
  ++ lib.optionals config.my.nixvim.full [
    ./lsp
    ./tree.nix
    # ./cmp.nix
    ./buffer.nix
    ./treesitter.nix
    # ./lualine.nix
    ./noice.nix
    ./transparent.nix
  ];
}

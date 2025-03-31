{ pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;

    # initExtraFirst = "
    # eval \"$(starship init zsh)\"
    # ";

    shellAliases = {
      vim = "nvim";
      g = "git";
      update-system = "cd ~/.config/nixos/ && git add -A && sudo nix flake update && sudo nixos-rebuild switch && git commit -m \"$(hostname) - Generation $(nixos-rebuild list-generations | grep current | awk '{print $1}') Successful Build\" && git push ; cd -";
      rebuild-system = "cd ~/.config/nixos/ && git add -A && sudo nixos-rebuild switch && git commit -m \"$(hostname) - Generation $(nixos-rebuild list-generations | grep current | awk '{print $1}') Successful Build (No flake update)\" && git push ; cd -";
    };

    plugins = [
      {
        name = "zsh-autosuggestions";
        src = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
        file = "zsh-autosuggestions.zsh";
      }
      {
        name = "nix-shell";
        src = "${pkgs.zsh-nix-shell}/share/zsh-nix-shell";
      }
      {
        name = "zsh-syntax-highlighting";
        src = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting";
        file = "zsh-syntax-highlighting.zsh";
      }
    ];
  };
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;
      format = ''[](#9A348E)\
$os\
$username\
[](bg:#DA627D fg:#9A348E)\
$directory\
[](fg:#DA627D bg:#FCA17D)\
$git_branch\
$git_status\
[](fg:#FCA17D bg:#86BBD8)\
$c\
$elixir\
$elm\
$golang\
$gradle\
$haskell\
$java\
$julia\
$nodejs\
$nim\
$rust\
$scala\
[](fg:#86BBD8 bg:#06969A)\
$docker_context\
[](fg:#06969A bg:#33658A)\
$time\
[ ](fg:#33658A)\'';
    };
  };
}

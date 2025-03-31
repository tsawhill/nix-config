{...}:
{
  programs.fish = {
    interactiveShellInit = ''
      ;
            set fish_greeting ''; # Disable greeting
    enable = true;
    shellAliases = {
      vim = "nvim";
      g = "git";
      update-system = "cd ~/.config/nixos/ && sudo nix flake update && sudo nixos-rebuild switch && git add -A && git commit -m \"$(hostname) - Generation $(nixos-rebuild list-generations | grep current | awk '{print $1}') Successful Build\" && git push ; cd -";
      rebuild-system = "cd ~/.config/nixos/ && sudo nixos-rebuild switch && git add -A && git commit -m \"$(hostname) - Generation $(nixos-rebuild list-generations | grep current | awk '{print $1}') Successful Build (No flake update)\" && git push ; cd -";
    };
  };
}

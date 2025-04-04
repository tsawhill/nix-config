{ pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;
    # dotDir = "/home/taylor/.config/zsh";

    shellAliases = {
      vim = "nvim";
      g = "git";
      update-system = "cd ~/.config/nixos/ && git add -A && sudo nix flake update && git add -A && sudo nixos-rebuild switch && git commit -m \"$(hostname) - Generation $(nixos-rebuild list-generations | grep current | awk '{print $1}') Successful Build\" && git push ; cd -";
      rebuild-system = "cd ~/.config/nixos/ && git add -A && sudo nixos-rebuild switch && git commit -m \"$(hostname) - Generation $(nixos-rebuild list-generations | grep current | awk '{print $1}') Successful Build (No flake update)\" && git push ; cd -";
    };

    initExtra = ''bindkey -e
      bindkey "^[[1;5D" backward-word 
      bindkey "^[[1;5C" forward-word
      bindkey "^[[1;3D" emacs-backward-word 
      bindkey "^[[1;3C" emacs-forward-word
      bindkey "^H" backward-kill-word
      bindkey "^[[3;5~" kill-word
      bindkey "\e[3~" delete-char

      autoload -U select-word-style
      select-word-style bash
      '';
    plugins = [
      {
        name = "zsh-syntax-highlighting";
        src = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting";
        file = "zsh-syntax-highlighting.zsh";
      }
      {
        name = "zsh-completions";
        src = "${pkgs.zsh-completions}/share/zsh-completions";
        file = "zsh-completions.zsh";
      }
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

  # autosuggestions settings
  home.sessionVariables = {
    ZSH_AUTOSUGGEST_STRATEGY = "history completion";
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE = "fg=140";
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = lib.mkMerge [
      (builtins.fromTOML (
        builtins.readFile "${pkgs.starship}/share/starship/presets/pastel-powerline.toml"
      ))
      {
        add_newline = false;
        command_timeout = 1500;
      }
    ];
  };
}

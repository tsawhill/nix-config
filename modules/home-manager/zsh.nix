{ pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;

    shellAliases = {
      vim = "nvim";
      g = "git";
      update-system = ''cd ~/.config/nixos/ && git add -A && sudo nix flake update && git add -A && sudo nixos-rebuild switch && git commit -m "$(hostname) - Generation $(nixos-rebuild list-generations | grep current | awk '{print $1}') Successful Build" && git push ; cd -'';
      rebuild-system = ''cd ~/.config/nixos/ && git add -A && sudo nixos-rebuild switch && git commit -m "$(hostname) - Generation $(nixos-rebuild list-generations | grep current | awk '{print $1}') Successful Build (No flake update)" && git push ; cd -'';
    };

    initContent = ''
            # Ensure we are using emacs mode (standard for zsh)
      bindkey -e

      # --- Navigation (Words & Lines) ---
      bindkey "^[[1;5C" forward-word                  # Ctrl + Right Arrow
      bindkey "^[[1;5D" backward-word                 # Ctrl + Left Arrow
      bindkey "^[[1;3C" emacs-forward-word            # Alt + Right Arrow
      bindkey "^[[1;3D" emacs-backward-word           # Alt + Left Arrow
      bindkey "^[[H"    beginning-of-line             # Home key
      bindkey "^[[F"    end-of-line                   # End key

      # --- History Searching ---
      # (Search history for what is already typed on the line)
      autoload -U up-line-or-beginning-search
      autoload -U down-line-or-beginning-search
      zle -N up-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey "^[[A" up-line-or-beginning-search      # Up Arrow
      bindkey "^[[B" down-line-or-beginning-search    # Down Arrow

      # --- Deletion & Editing ---
      bindkey "^H"      backward-kill-word            # Ctrl + Backspace (usually)
      bindkey "^[[3;5~" kill-word                     # Ctrl + Delete
      bindkey "\e[3~"   delete-char                   # Standard Delete key
      bindkey "^?"      backward-delete-char          # Standard Backspace
      bindkey "^_"      undo                          # Ctrl + / (Undo)

      # --- Buffer Management ---
      # Open the current command in your default $EDITOR (vim/nano)
      autoload -U edit-command-line
      zle -N edit-command-line
      bindkey '^xe' edit-command-line
      bindkey '^x^e' edit-command-line

      # --- Completion Menu ---
      bindkey '^[[Z' reverse-menu-complete            # Shift + Tab (go backward in list)

      # --- Word Style Selection ---
      autoload -U select-word-style
      select-word-style bash
    '';
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

  # autosuggestions settings
  home.sessionVariables = {
    ZSH_AUTOSUGGEST_STRATEGY = "history completion";
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE = "fg=140";
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = lib.mkMerge [
      (builtins.fromTOML (builtins.readFile "${pkgs.starship}/share/starship/presets/pure-preset.toml"))
      {
        add_newline = lib.mkForce false;
        command_timeout = 1500;
      }
    ];
  };
}

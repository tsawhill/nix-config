# Shared by the HM starship module and the NixOS headless shell.
server: {
  add_newline = false;
  palette = "tokyo_night";
  format = "$username$hostname$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character";
  palettes.tokyo_night = {
    blue = "#7aa2f7";
    purple = "#bb9af7";
    cyan = "#7dcfff";
    green = "#9ece6a";
    red = "#f7768e";
    amber = "#e0af68";
  };
  username = {
    show_always = server;
    style_user = "bold amber";
    style_root = "bold red";
    format = "[$user]($style)[@](bold amber)";
  };
  hostname = {
    ssh_only = !server;
    style = "bold amber";
    format = "[$hostname]($style) ";
  };
  directory = {
    style = if server then "bold amber" else "bold blue";
    truncation_length = 3;
  };
  git_branch = {
    symbol = "git:";
    style = "purple";
  };
  git_status.style = "red";
  nix_shell = {
    symbol = "nix ";
    format = "[($symbol$state )]($style)";
    style = "cyan";
  };
  cmd_duration = {
    min_time = 2000;
    style = "amber";
  };
  character = {
    success_symbol = if server then "[❯](bold amber)" else "[❯](bold purple)";
    error_symbol = "[❯](bold red)";
  };
}

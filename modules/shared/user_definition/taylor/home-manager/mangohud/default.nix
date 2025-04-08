{ pkgs, ... }:
{
  programs.mangohud = {
    enable = true;
    enableSessionWide = true;
    settings = {
      font_file = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/DaddyTimeMono/DaddyTimeMonoNerdFont-Regular.ttf";
      position = "top-right";
      frame_timing = 0;
      height = 300;
      width = 300;
      gpu_stats = true;
      gpu_temp = true;
      cpu_stats = true;
      cpu_temp = true;
      hud_compact = true;
      output_folder = /tmp;
    };
    settingsPerApplication = {
      gamescope = {
        no_display = true;
      };
    };
  };
}

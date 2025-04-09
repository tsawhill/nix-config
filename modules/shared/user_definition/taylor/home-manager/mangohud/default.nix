{ pkgs, ... }:
{
  programs.mangohud = {
    enable = true;
    enableSessionWide = true;
    settings = {
      font_file = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/DaddyTimeMono/DaddyTimeMonoNerdFont-Regular.ttf";
      position = "top-right";
      frame_timing = 0;
      height = 200;
      width = 200;
      gpu_stats = true;
      gpu_temp = true;
      cpu_stats = true;
      cpu_temp = true;
      hud_compact = true;
      output_folder = /tmp;
    };
    settingsPerApplication = {
      walker = {
        no_display = true;
      };
      gamescope = {
        no_display = true;
      };
    };
  };
}

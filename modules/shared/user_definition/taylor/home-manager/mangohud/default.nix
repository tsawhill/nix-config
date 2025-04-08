{ pkgs, ... }: {
  programs.mangohud = {
    enable = true;
    enableSessionWide = true;
    settings = {
      font_file =
        "${pkgs.nerd-fonts.daddy-time-mono}/share/fonts/truetype/NerdFonts/DaddyTimeMono/DaddyTimeMonoNerdFont-Regular.ttf";
      position = "top-right";
      font_scale = 1.5;
      gpu_stats = true;
      cpu_stats = true;
      output_folder = /tmp;
    };
  };
}

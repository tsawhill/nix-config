{ pkgs, ... }: {
  programs.mangohud = {
    enable = true;
    enableSessionWide = true;
    settings = {
      font_file =
        "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/DaddyTimeMono/DaddyTimeMonoNerdFont-Regular.ttf";
      position = "top-right";
      font_size = 28;
      frame_timing = 0;
      height = 200;
      width = 200;
      gpu_stats = true;
      cpu_stats = true;
      output_folder = /tmp;
    };
  };
}

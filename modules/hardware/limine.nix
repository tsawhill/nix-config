{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.boot.limine;

  # Wallpaper Engine can't run before boot, so draw a still one at build time:
  # a pink-to-lavender gradient with soft bokeh and glowing four-point sparkles.
  star =
    x: y: r:
    let
      s = r / 4;
      p = dx: dy: "${toString (x + dx)},${toString (y + dy)}";
    in
    ''-draw "polygon ${p 0 (-r)} ${p s (-s)} ${p r 0} ${p s s} ${p 0 r} ${p (-s) s} ${p (-r) 0} ${p (-s) (-s)}"'';
  sparkles = lib.concatStringsSep " " [
    (star 310 180 22)
    (star 1010 420 14)
    (star 2290 150 26)
    (star 1780 640 16)
    (star 620 1180 20)
    (star 2120 1290 14)
    (star 1460 1040 24)
    (star 180 820 12)
    (star 2420 900 18)
    (star 860 760 12)
    (star 1250 300 10)
    (star 2000 470 10)
  ];
  wallpaper =
    pkgs.runCommand "limine-pastel-wallpaper.png" { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        magick -size 2560x1440 -define gradient:direction=SouthEast 'gradient:#FAD6EC-#D7CBF7' \
          \( -size 2560x1440 xc:none -fill 'rgba(255,255,255,0.45)' \
             -draw "circle 420,330 420,560" -draw "circle 2160,250 2160,410" \
             -draw "circle 1890,1170 1890,1450" -draw "circle 280,1240 280,1370" \
             -draw "circle 1300,140 1300,230" -blur 0x45 \) -composite \
          \( -size 2560x1440 xc:none -fill 'rgba(255,170,215,0.40)' \
             -draw "circle 1050,980 1050,1130" -draw "circle 2380,620 2380,760" \
             -draw "circle 700,560 700,640" -blur 0x30 \) -composite \
          \( -size 2560x1440 xc:none -fill white ${sparkles} \
             \( +clone -blur 0x10 \) +swap -composite \) -composite \
          $out
      '';
in
{
  options.my.boot.limine = {
    enable = lib.mkEnableOption "the Limine bootloader with the pastel theme";

    fontScale = lib.mkOption {
      type = lib.types.str;
      default = "2x2";
      description = "Menu font scale (<width>x<height>); 1x1 suits small screens.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.loader.systemd-boot.enable = false;
    # Valve firmware boots the disk's default \EFI\BOOT\BOOTX64.EFI ahead of any
    # named entry, so install Limine there instead of adding an NVRAM entry.
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
    boot.loader.limine = {
      enable = true;
      efiInstallAsRemovable = true;
      maxGenerations = 10;
      style = {
        wallpapers = [ wallpaper ];
        wallpaperStyle = "stretched";
        interface = {
          branding = "~ * ${config.networking.hostName} * ~";
          brandingColor = "D6338A";
          helpColor = "8E5BB5";
          helpColorBright = "D6338A";
        };
        graphicalTerminal = {
          font.scale = cfg.fontScale;
          # Light panel: pale pink, a little see-through (TT = transparency), plum text.
          background = "70FFF2F9";
          foreground = "4A2545";
          brightBackground = "F4D8EE";
          brightForeground = "2E1630";
          # black red green brown blue magenta cyan gray, tuned for a light background
          palette = "4A2545;D6338A;4F9D7A;C77D3A;7A5BC7;B4479A;3E8E9E;F7E8F3";
          brightPalette = "8C6A8A;F25CA2;7CC5A0;E8A85C;A88BEB;E07BC4;6CC0CC;FFFFFF";
          margin = 96;
          marginGradient = 48;
        };
      };
    };
  };
}

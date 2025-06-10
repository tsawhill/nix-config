# Nix settings
{
  imports = [
    ./usbmounts.nix
    ./polkit.nix
  ];

  nix = {
    settings = {
      # Since config is stored in a git repository and changes are not pushed until a successful build
      warn-dirty = false;

      max-jobs = 4;
      cores = 2;

      substituters = [
        "https://walker-git.cachix.org/"
        "https://hyprland.cachix.org/"
      ];
      trusted-public-keys = [
        "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "taylor"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
}

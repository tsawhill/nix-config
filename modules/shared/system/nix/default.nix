# Nix settings
{
  imports = [
    ./usbmounts.nix
  ];
  nix = {
    settings = {
      # Since config is stored in a git repository and changes are not pushed until a successful build
      warn-dirty = false;

      substituters = [
        "https://walker.cachix.org/"
        "https://hyprland.cachix.org/"
      ];
      trusted-public-keys = [
        "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
}

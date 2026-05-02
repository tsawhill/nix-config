{
  imports = [
    ./profiles.nix
    ./instances.nix
  ];

  my.incusDeclarative = {
    enable = true;
    mode = "non-destructive";
  };
}

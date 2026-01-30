{
  nix.settings = {
    # Protects the dependencies of any active process or shell
    keep-outputs = true;
    keep-derivations = true;
  };
}

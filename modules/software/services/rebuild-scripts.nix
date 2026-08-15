# Compatibility import: callers keep the old module path while implementation
# lives beside the Rust controller's focused Nix wiring.
{
  imports = [ ./rebuild ];
}

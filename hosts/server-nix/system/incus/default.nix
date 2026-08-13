{
  # Sunshine creates its keyboard and mouse through /dev/uinput. Label only
  # those synthetic event devices so Incus's unix-hotplug matcher can pass
  # their device nodes and uevents into sunshine-nix for KWin/libinput.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="beef", ATTRS{id/product}=="dead", ENV{ID_VENDOR_ID}="beef", ENV{ID_MODEL_ID}="dead"
  '';

  my.incusDeclarative = {
    enable = true;
    mode = "non-destructive";
    profilesFile = ./profiles.yaml;
    instancesFile = ./instances.yaml;
  };
}

{
  imports = [ ../../../../modules/software/services/usbip-tray.nix ];
  my.usbip = {
    enable = true;
    exporter = false;
    containerRecipient = "sunshine-nix";
  };

  # Sunshine creates its keyboard and mouse through /dev/uinput. Label only
  # those synthetic event devices so Incus's unix-hotplug matcher can pass
  # their device nodes and uevents into sunshine-nix for KWin/libinput.
  # Incus matches unix-hotplug devices on ID_VENDOR_ID and ID_MODEL_ID, so a
  # device is only passed through once udev has published both.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{id/vendor}=="beef", ATTRS{id/product}=="dead", ENV{ID_VENDOR_ID}="beef", ENV{ID_MODEL_ID}="dead"

    # A USB/IP import hangs off vhci_hcd rather than a USB controller, so udev
    # calls its input children platform devices and never runs usb_id on them.
    # Their hidraw and bus/usb siblings are unaffected and already carry the
    # IDs. Scoped to imports: devices plugged into this host stay unmatched.
    SUBSYSTEM=="input", DEVPATH=="/devices/platform/vhci_hcd.*", ENV{ID_VENDOR_ID}=="", ATTRS{idVendor}=="?*", ENV{ID_VENDOR_ID}="$attr{idVendor}", ENV{ID_MODEL_ID}="$attr{idProduct}"
  '';

  my.incusDeclarative = {
    enable = true;
    mode = "non-destructive";
    profilesFile = ./profiles.yaml;
    instancesFile = ./instances.yaml;
  };
}

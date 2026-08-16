{ ... }:
{
  boot.loader.systemd-boot = {
    enable = true;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Valve's kernel (with the CEC adapter drivers now enabled in linux-jovian
  # itself), the Switch/DualSense HID preloads and the initrd storage modules
  # all come from jovian.devices.steammachine — see hosts/taylor-cube-nix.

  # RetroCultMods "MiniHost" GH Guitar adapter (VID:PID 1209:2882) intermittently
  # self-resets/disconnects on this xHCI-only box. Disable USB Link Power
  # Management for just that device (quirk "k" = USB_QUIRK_NO_LPM) — a common fix
  # for devices that drop off xHCI. Scoped to the one VID:PID, fully reversible.
  boot.kernelParams = [ "usbcore.quirks=1209:2882:k" ];
}

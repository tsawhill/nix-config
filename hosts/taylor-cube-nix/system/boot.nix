{ lib, pkgs, ... }:
{
  boot.loader.systemd-boot = {
    enable = true;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Valve's kernel. Mainline amdgpu only registers a CEC adapter for DP-to-HDMI
  # tunneling-over-AUX, so nothing appears for the Steam Machine's HDMI port
  # (driven through a DP-HDMI FRL PCON) and cecd starts with zero devices. CEC
  # over HDMI works on stock SteamOS, so the enablement is in Valve's tree.
  # Set directly rather than via jovian.devices.steamdeck.enableKernelPatches:
  # that option also adds fbcon=rotate:1 for the Deck's portrait panel.
  boot.kernelPackages = pkgs.linuxPackages_jovian;

  # The other half of enableKernelPatches — preload for Switch/DualSense pads.
  boot.kernelModules = [
    "hid_nintendo"
    "hid_playstation"
  ];

  # CEC hangs off the ChromeOS-style EC: cros-ec-cec.2.auto enumerates but binds
  # nothing, since drivers/media/cec/platform/* is gated behind MEDIA_CEC_SUPPORT,
  # which no stock kernel config sets. kernelPatches merges into the kernel's own
  # structuredExtraConfig; .override would clobber linux-jovian's.
  boot.kernelPatches = [
    {
      name = "cec-cros-ec";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        MEDIA_CEC_SUPPORT = yes;
        CEC_CROS_EC = module;
      };
    }
    # Fremont's DMI entry asks for connector "Port C", but amdgpu registers its
    # notifier unnamed, so the adapter gets an orphan and stays at f.f.f.f.
    {
      name = "cros-ec-cec-fremont-connector";
      patch = ./patches/cros-ec-cec-fremont-connector.patch;
    }
  ];

  # RetroCultMods "MiniHost" GH Guitar adapter (VID:PID 1209:2882) intermittently
  # self-resets/disconnects on this xHCI-only box. Disable USB Link Power
  # Management for just that device (quirk "k" = USB_QUIRK_NO_LPM) — a common fix
  # for devices that drop off xHCI. Scoped to the one VID:PID, fully reversible.
  boot.kernelParams = [ "usbcore.quirks=1209:2882:k" ];

  # Storage controllers needed in the initrd to reach the root filesystem
  # (from nixos-generate-config on this machine).
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
}

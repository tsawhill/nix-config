# Windows SSD VM on taylor-desktop-nix

Use the existing Windows installation for USB utilities with libvirt/KVM and
virt-manager. The VM writes directly to the real Windows SSD; back up important
files before first boot. Do not create or format a new volume on this disk.

## Before first boot

1. In native Windows, disable Fast Startup/hibernation (`powercfg /h off` in an
   administrator terminal), then shut down fully. If BitLocker/device encryption
   is enabled, have the recovery key available: virtual hardware and a virtual
   TPM differ from the physical machine. Never put the key in this repository.
2. Obtain the whole-disk stable path on the desktop:

   ```sh
   find -L /dev/disk/by-id -maxdepth 1 -samefile /dev/nvme1n1
   ```

   Use a whole-disk `/dev/disk/by-id/nvme-...` path, without `-partN`. Passing only
   C: omits the EFI boot partition. Confirm the disk's model and capacity with
   `lsblk -o NAME,SIZE,MODEL,MOUNTPOINTS`.
3. Deploy the NixOS configuration after approval, then log out and back in for
   libvirtd group membership. The config makes `/mnt/windows` manual/read-only;
   this is not a lock against later manual mounts.
4. Run `sudo umount /mnt/windows` if it is still mounted. Check `lsblk` and ensure
   **all** partitions of the SSD are unmounted. Never mount any of them in Linux
   while the VM is running, even read-only. Do not suspend/save the VM and then
   boot native Windows; fully shut it down before switching environments.

## Open the configured VM

Deployment defines **windows-ssd** without starting it. In virt-manager connect
to **QEMU/KVM system** (`qemu:///system`) and open that guest. The declarative
definition is `hosts/taylor-desktop-nix/system/windows-ssd.xml`; edit that file
for persistent hardware changes, since deployment reapplies it. Defaults:

- Q35 machine with UEFI firmware.
- Existing disk: raw format, SATA bus, cache mode `none`. SATA avoids needing
  VirtIO storage drivers before the first boot.
- Default NAT network and an e1000e NIC for initial driver compatibility.
- SPICE display, basic video, USB tablet, and a USB 3 controller.
- Emulated TPM 2.0; this cannot unlock encryption tied to the host TPM.
- Keep VM autostart disabled.

The guest uses 4 vCPUs and 8 GiB RAM. Its SATA disk is
`/dev/disk/by-id/nvme-SPCC_M.2_PCIe_SSD_30083920240` (the entire 476.9 GiB SSD).
A libvirt prepare hook checks block disks and their partitions and rejects VM
startup if any are mounted. This is a startup check, not a lock against mounting
them later; leave the disk unmounted until Windows shuts down completely.

If the default network is inactive, start it with
`sudo virsh -c qemu:///system net-start default`. If UEFI does not discover
Windows automatically, use its boot menu to select the SSD's
`EFI/Microsoft/Boot/bootmgfw.efi`. Do not reinstall Windows or format the SSD.

## USB firmware utilities

Use **Add Hardware → USB Host Device** to attach the peripheral. It becomes
unavailable to Linux while assigned. A firmware updater may reconnect the device
with a different USB ID in bootloader mode; that device may also need attaching.
Check the vendor's VM support before flashing. If reconnects prevent reliable
operation, boot native Windows for that update. Avoid suspending the host or VM
during an update.

References: [NixOS libvirt setup](https://wiki.nixos.org/wiki/Libvirt) and
[libvirt disk/USB domain configuration](https://libvirt.org/formatdomain.html).

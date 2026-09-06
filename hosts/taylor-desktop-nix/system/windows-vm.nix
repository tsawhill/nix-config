{ pkgs, ... }:
{
  # UEFI firmware is supplied by the libvirt QEMU package.
  virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;
    hooks.qemu.windows-ssd = pkgs.writeScript "windows-ssd-mount-check" ''
      #!${pkgs.python3}/bin/python3
      import json
      import subprocess
      import sys
      import xml.etree.ElementTree as ET

      if sys.argv[2:4] != ["prepare", "begin"]:
          sys.exit(0)
      domain = ET.parse(sys.stdin).getroot()
      for source in domain.findall("./devices/disk[@type='block']/source"):
          disk = source.get("dev")
          if not disk:
              continue
          result = subprocess.run(
              ["${pkgs.util-linux}/bin/lsblk", "--json", "--output", "NAME,MOUNTPOINTS", disk],
              check=True, capture_output=True, text=True,
          )
          def check(devices):
              for device in devices:
                  if any(device.get("mountpoints") or []):
                      sys.exit("Refusing VM startup: " + device["name"] + " is mounted. Unmount all partitions first.")
                  check(device.get("children", []))
          check(json.loads(result.stdout)["blockdevices"])
    '';
  };
  programs.virt-manager.enable = true;
  environment.systemPackages = [ (import ../../../pkgs/vm-usb-port { inherit pkgs; }) ];
  virtualisation.spiceUSBRedirection.enable = true;
  my.users.taylor.extraGroups = [ "libvirtd" ];

  # Define the guest without starting it or touching the Windows filesystem.
  systemd.services.windows-ssd-define = {
    description = "Define the Windows SSD virtual machine";
    wantedBy = [ "multi-user.target" ];
    requires = [ "libvirtd.service" ];
    after = [ "libvirtd.service" ];
    restartTriggers = [ ./windows-ssd.xml ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      ${pkgs.libvirt}/bin/virsh --connect qemu:///system define ${./windows-ssd.xml}
      ${pkgs.libvirt}/bin/virsh --connect qemu:///system autostart --disable windows-ssd
    '';
  };
}

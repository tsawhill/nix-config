{ pkgs }:
let
  launcher = pkgs.writeShellApplication {
    name = "vm-usb-port";
    runtimeInputs = [
      pkgs.python3
      pkgs.libvirt
      pkgs.zenity
    ];
    text = ''
      exec python3 ${./vm-usb-port.py} "$@"
    '';
  };
  desktop = pkgs.makeDesktopItem {
    name = "vm-usb-port";
    desktopName = "VM USB Port";
    comment = "Attach a USB port to a VM for the current session";
    exec = "${launcher}/bin/vm-usb-port";
    icon = "usb-creator";
    categories = [
      "System"
      "Utility"
    ];
    terminal = false;
  };
in
pkgs.symlinkJoin {
  name = "vm-usb-port";
  paths = [
    launcher
    desktop
  ];
}

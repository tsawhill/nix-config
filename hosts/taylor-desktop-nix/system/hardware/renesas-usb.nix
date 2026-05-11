{ lib, pkgs, ... }:
let
  renesasUsbFirmwareBlob = pkgs.fetchurl {
    name = "renesas_usb_fw.mem";
    url = "https://web.archive.org/web/20240316231746if_/https://raw.githubusercontent.com/denisandroid/uPD72020x-Firmware/master/UPDATE.mem";
    hash = "sha512-HqEX+aGncgE/t1Ccdtcxhl5sBa48VaME/0KzHsikdOm/Ft0bBbLltmbsX9MBrv7VS/62v9fD8j3CP68ILPKp9w==";
  };

  renesasUsbFirmware = pkgs.runCommand "renesas-upd72020x-firmware"
    {
      meta = {
        description = "Renesas uPD720201/uPD720202 USB 3.0 controller firmware";
        license = lib.licenses.unfreeRedistributableFirmware;
        platforms = lib.platforms.linux;
      };
    }
    ''
      install -Dm444 ${renesasUsbFirmwareBlob} $out/lib/firmware/renesas_usb_fw.mem
    '';
in
{
  # The MOTU M2 is attached to the Renesas uPD720201 controller on this host.
  # Keep this to kernel firmware loading only; do not flash the controller EEPROM.
  hardware.firmware = [ renesasUsbFirmware ];
}

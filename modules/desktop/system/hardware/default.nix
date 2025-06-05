{
  ...
}:
{
  # For Logitech G923 Racing Wheel
  # hardware.new-lg4ff.enable = true;

  # Enable ntfs for windows disk
  boot.supportedFilesystems = [ "ntfs" ];
  fileSystems."/mnt/windows" = {
    device = "/dev/nvme1n1p3";
    fsType = "ntfs-3g";
    options = [
      "rw"
      "uid=1000"
      "nofail"
    ];
  };

}

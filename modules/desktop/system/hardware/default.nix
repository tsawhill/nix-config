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
  services.lact = {
    enable = false;
    settings = {
      version = 5;
      daemon = {
        log_level = "info";
        admin_group = "wheel";
        disable_clocks_cleanup = false;
      };
      apply_settings_timer = 5;
      gpus = {
        "1002:744C-1EAE:7905-0000:03:00.0" = {
          fan_control_enabled = false;
          pmfw_options = {
            zero_rpm = true;
          };
          power_cap = 290.0;
          performance_level = "manual";
          max_core_clock = 2535;
          voltage_offset = -50;
          power_profile_mode_index = 1;
        };
      };
      current_profile = null;
      auto_switch_profiles = false;
    };
  };
  hardware.amdgpu.overdrive.enable = false;

}

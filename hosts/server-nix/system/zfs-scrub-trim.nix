{
  services.zfs = {
    # 1. Automated Scrubs (The Unraid Parity Check Equivalent)
    autoScrub = {
      enable = true;
      # Runs weekly on Sunday at 2:00 AM. You can change this to "monthly"
      # or a specific systemd calendar format if you prefer.
      interval = "monthly";

      # Optional: List specific pools to scrub.
      # If you comment this out or remove it, NixOS will scrub all healthy pools.
      # pools = [ "rpool" "data" ];
    };

    # 2. Automated TRIM (Essential for SSDs/NVMe drives)
    trim = {
      enable = true;
      # Runs weekly. ZFS will issue TRIM commands to SSDs to free up unused blocks.
      interval = "monthly";
    };
  };
}

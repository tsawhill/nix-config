{ config, pkgs, ... }:

let
  createNixosScript = pkgs.writeShellScriptBin "create-nixos" ''
        set -e
        
        # --- Dependencies ---
        GUM="${pkgs.gum}/bin/gum"
        PV="${pkgs.pv}/bin/pv"
        FIGLET="${pkgs.figlet}/bin/figlet"

        # --- Configuration ---
        IMAGE_ALIAS="nixos-base-image"
        PROFILE="nixos-lxc"
        ROOT_POOLS=("rpool" "downloadHDD" "VMDisks")
        
        # ZFS Settings matching your disks.nix [cite: 31, 38]
        NIX_TEMPLATE_SNAPSHOT="rpool/VMDisks/nix-templates/nixos-base-nix@ready"
        NIX_PARENT_DATASET="downloadHDD/nix-stores"
        NIX_HOST_MOUNT_BASE="/mnt/nix-stores"
        
        UID_GID="100000:100000"

        # --- UI Splash ---
        clear
        $GUM style --foreground 86 --border-foreground 86 --border double --align center --width 50 "$($FIGLET -f small "NIXOS FACTORY")"
        
        # --- Input Collection ---
        HOSTNAME=$($GUM input --placeholder "Enter the new container hostname")
        if [ -z "$HOSTNAME" ]; then exit 1; fi

        $GUM style --foreground 212 "󰆼 Select Target Root Storage Pool:"
        SELECTED_POOL=$($GUM choose "''${ROOT_POOLS[@]}")
        
        # --- MAC Address Selection (Restored) ---
        MAC_ADDR=$($GUM input --placeholder "MAC Address (Leave blank for auto-generate)")
        if [ -z "$MAC_ADDR" ]; then
          MAC_ADDR=$(printf '02:%02X:%02X:%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
          $GUM style --foreground 212 "󰂪 Generated MAC: $MAC_ADDR"
        fi

        # --- Step 1: Incus Init ---
        echo "==> Initializing Root FS on $SELECTED_POOL..."
        incus init "$IMAGE_ALIAS" "$HOSTNAME" -p "$PROFILE" -s "$SELECTED_POOL"

        # --- Step 2: ZFS Send/Receive ---
        DATASET_NAME="''${NIX_TEMPLATE_SNAPSHOT%@*}"
        SIZE=$(sudo zfs list -H -p -o referenced "$DATASET_NAME")
        
        echo "==> Replicating store to $NIX_PARENT_DATASET/$HOSTNAME..."
        sudo zfs send "$NIX_TEMPLATE_SNAPSHOT" | $PV -p -s "$SIZE" | sudo zfs receive "$NIX_PARENT_DATASET/$HOSTNAME"

        # --- Step 3: Permissions & Wiring ---
        # We rely on your existing ZFS inheritance to populate /mnt/nix-stores/$HOSTNAME [cite: 31]
        $GUM spin --spinner pulse --title "Configuring devices..." -- bash -c "
          # Fix permissions for the container user [cite: 44]
          sudo chown -R $UID_GID $NIX_HOST_MOUNT_BASE/$HOSTNAME
          
          # Attach the HDD store to the container's /nix path [cite: 45]
          incus config device add $HOSTNAME nix-store disk source=$NIX_HOST_MOUNT_BASE/$HOSTNAME path=/nix
          
          # Configure Network with the selected/generated MAC 
          if incus config device show $HOSTNAME | grep -q '^eth0:'; then
            incus config device set $HOSTNAME eth0 hwaddr=$MAC_ADDR
          else
            incus config device add $HOSTNAME eth0 nic nictype=bridged parent=br0 hwaddr=$MAC_ADDR
          fi
        "

        # --- Step 4: Final Launch ---
        $GUM confirm "Ready to launch $HOSTNAME?" && incus start "$HOSTNAME"
        
        $GUM style --foreground 82 --border rounded --padding "1 2" "󰄬 Successfully deployed $HOSTNAME!
    Root: $SELECTED_POOL
    MAC:  $MAC_ADDR
    Store: $NIX_HOST_MOUNT_BASE/$HOSTNAME"
  '';
in
{
  environment.systemPackages = [
    pkgs.gum
    pkgs.pv
    pkgs.figlet
    createNixosScript
  ];
}

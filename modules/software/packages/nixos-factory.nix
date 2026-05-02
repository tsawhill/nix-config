{ config, pkgs, ... }:

let
  nixosFactoryScript = pkgs.writeShellScriptBin "nixos-factory" ''
    set -e

    # --- Tool paths (pinned to nix store) ---
    GUM="${pkgs.gum}/bin/gum"
    FIGLET="${pkgs.figlet}/bin/figlet"
    PV="${pkgs.pv}/bin/pv"
    JQ="${pkgs.jq}/bin/jq"

    # --- Incus / ZFS defaults ---
    IMAGE_ALIAS="nixos-base-image"       # local image alias for base NixOS LXC
    PROFILE="nixos-lxc"                  # default profile applied to new containers
    ROOT_POOLS=("rpool" "downloadHDD" "VMDisks")  # ZFS pools the user can pick from

    # Template nix store snapshot — cloned into each new container so it has a
    # working /nix from the start (avoids a full download on first deploy).
    NIX_TEMPLATE_SNAPSHOT="rpool/VMDisks/nix-templates/nixos-base-nix@ready"

    # Parent ZFS dataset under which per-container nix stores live.
    # e.g. downloadHDD/nix-stores/jellyfin-nix
    NIX_PARENT_DATASET="downloadHDD/nix-stores"

    # Host-side mount base — each container's nix store is bind-mounted from
    # $NIX_HOST_MOUNT_BASE/<hostname> into the container at /nix.
    NIX_HOST_MOUNT_BASE="/mnt/nix-stores"

    # UID/GID the nix store is chowned to — matches the container's id mapping
    # (security.idmap.base = 100000 in the nixos-lxc profile).
    UID_GID="100000:100000"

    # SSH key for factory → build-nix deploys (managed by sops)
    FACTORY_SSH_KEY="/run/secrets/server_nix_factory_id_ed25519"

    # --- Nix config repo paths (on server-nix) ---
    NIX_CONFIG="/mnt/zpool/code/nix-config"
    INSTANCES_YAML="$NIX_CONFIG/hosts/server-nix/system/incus/instances.yaml"
    COLMENA_NIX="$NIX_CONFIG/flake-outputs/colmena.nix"

    # ── Splash screen ─────────────────────────────────────────────
    clear
    $GUM style --foreground 86 --border-foreground 86 --border double \
      --align center --width 50 "$($FIGLET -f small "NIXOS FACTORY")"

    # Top-level action picker
    ACTION=$($GUM choose "create" "rename" "delete")

    # ══════════════════════════════════════════════════════════════
    #  CREATE — provision a new NixOS container end-to-end
    #
    #  Flow:
    #    1. Prompt for hostname
    #    2. Verify a NixOS / colmena config already exists for it
    #    3. Collect storage pool + MAC address
    #    4. Show plan and confirm
    #    5. Create Incus container from base image
    #    6. Clone the template nix store via ZFS send/receive
    #    7. Wire up devices (nix-store disk, eth0 NIC)
    #    8. Append instance to instances.yaml (declarative config)
    #    9. Start the container, wait for network
    #   10. SSH to build-nix and deploy the NixOS config
    # ══════════════════════════════════════════════════════════════
    do_create() {
      HOSTNAME=$($GUM input --placeholder "Enter the new container hostname")
      if [ -z "$HOSTNAME" ]; then exit 1; fi

      # --- Pre-flight checks ---

      # The container must have a NixOS config + colmena deployment entry
      # BEFORE we create the Incus container. If it doesn't, abort so the
      # user can write the config first.
      if ! grep -q "\"$HOSTNAME\"" "$COLMENA_NIX"; then
        $GUM style --foreground 196 --bold "No colmena config found for $HOSTNAME"
        $GUM style --foreground 214 \
          "Create a NixOS config at hosts/server-nix/LXCs/ and add a colmena entry first."
        exit 1
      fi

      # Don't clobber an existing container
      if incus info "$HOSTNAME" >/dev/null 2>&1; then
        $GUM style --foreground 196 "Container $HOSTNAME already exists in Incus."
        exit 1
      fi

      # --- Collect parameters ---

      $GUM style --foreground 212 "Select target root storage pool:"
      SELECTED_POOL=$($GUM choose "''${ROOT_POOLS[@]}")

      # MAC can be manually specified (e.g. to match a DHCP reservation)
      # or auto-generated with a locally-administered prefix (02:xx:xx:xx:xx:xx).
      MAC_ADDR=$($GUM input --placeholder "MAC address (leave blank to auto-generate)")
      if [ -z "$MAC_ADDR" ]; then
        MAC_ADDR=$(printf '02:%02X:%02X:%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
        $GUM style --foreground 212 "Generated MAC: $MAC_ADDR"
      fi

      # --- Show plan and confirm ---
      echo ""
      $GUM style --foreground 86 --bold "Create plan:"
      echo "  Hostname:  $HOSTNAME"
      echo "  Pool:      $SELECTED_POOL"
      echo "  MAC:       $MAC_ADDR"
      echo "  Store:     $NIX_HOST_MOUNT_BASE/$HOSTNAME"
      echo "  YAML:      $INSTANCES_YAML (will be updated)"
      echo "  Deploy:    ssh build-nix.lan deploy $HOSTNAME"
      echo ""

      if ! $GUM confirm "Create container?"; then
        $GUM style --foreground 214 "Aborted."
        exit 0
      fi

      # --- Step 1: Create the Incus container ---
      # Uses the base NixOS image and the nixos-lxc profile for defaults
      # (2 CPU, 2GiB RAM, nesting, idmap, bridged networking).
      echo "==> Initializing root FS on $SELECTED_POOL..."
      incus init "$IMAGE_ALIAS" "$HOSTNAME" -p "$PROFILE" -s "$SELECTED_POOL"

      # --- Step 2: Clone the template nix store ---
      # ZFS send/receive copies the pre-built /nix from the template snapshot
      # into a new dataset for this container. pv shows a progress bar.
      DATASET_NAME="''${NIX_TEMPLATE_SNAPSHOT%@*}"
      SIZE=$(sudo zfs list -H -p -o referenced "$DATASET_NAME")

      echo "==> Replicating nix store to $NIX_PARENT_DATASET/$HOSTNAME..."
      sudo zfs send "$NIX_TEMPLATE_SNAPSHOT" | $PV -p -s "$SIZE" | sudo zfs receive "$NIX_PARENT_DATASET/$HOSTNAME"

      # --- Step 3: Wire up devices ---
      # - chown the nix store to the container's mapped UID/GID
      # - Attach the host-side nix store as a disk device at /nix
      # - Set or create the eth0 NIC with the chosen MAC address
      $GUM spin --spinner pulse --title "Configuring devices..." -- bash -c "
        sudo chown -R $UID_GID $NIX_HOST_MOUNT_BASE/$HOSTNAME

        incus config device add $HOSTNAME nix-store disk source=$NIX_HOST_MOUNT_BASE/$HOSTNAME path=/nix

        if incus config device show $HOSTNAME | grep -q '^eth0:'; then
          incus config device set $HOSTNAME eth0 hwaddr=$MAC_ADDR
        else
          incus config device add $HOSTNAME eth0 nic nictype=bridged parent=br0 hwaddr=$MAC_ADDR
        fi
      "

      # --- Step 4: Add to declarative config ---
      # Append this instance to instances.yaml so incus-declarative-apply
      # and incus-sync know about it without needing a manual pull.
      echo "==> Adding $HOSTNAME to instances.yaml..."
      cat >> "$INSTANCES_YAML" <<YAML

$HOSTNAME:
  type: "container"
  profiles: ["nixos-lxc"]
  config: {}
  devices:
    root: { type: "disk", path: "/", pool: "$SELECTED_POOL", size: "4GiB" }
    nix-store: { type: "disk", path: "/nix", source: "$NIX_HOST_MOUNT_BASE/$HOSTNAME" }
    eth0: { type: "nic", nictype: "bridged", parent: "br0", hwaddr: "$MAC_ADDR" }
YAML

      # --- Step 5: Start and wait for network ---
      # The container boots with the base NixOS image. We need it to get a
      # DHCP lease and be reachable before we can deploy the real config.
      echo "==> Starting $HOSTNAME..."
      incus start "$HOSTNAME"

      echo "==> Waiting for $HOSTNAME to get network..."
      for i in $(seq 1 30); do
        if incus exec "$HOSTNAME" -- ping -c1 -W1 build-nix.lan >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      # --- Step 6: Deploy NixOS config ---
      # SSH to build-nix (the colmena deployment host) and trigger a deploy.
      # This builds the NixOS config and pushes it to the new container.
      echo "==> Deploying NixOS config via build-nix..."
      ssh -i "$FACTORY_SSH_KEY" -o IdentitiesOnly=yes root@build-nix.lan "deploy $HOSTNAME"

      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Successfully created and deployed $HOSTNAME
    Pool:  $SELECTED_POOL
    MAC:   $MAC_ADDR
    Store: $NIX_HOST_MOUNT_BASE/$HOSTNAME"
    }

    # ══════════════════════════════════════════════════════════════
    #  RENAME — rename a container + its nix store
    #
    #  Flow:
    #    1. Pick container from list
    #    2. Enter new name, validate it's free
    #    3. Show plan and confirm
    #    4. Stop container if running
    #    5. Rename the Incus container
    #    6. Rename the ZFS nix store dataset
    #    7. Update the nix-store device source path
    #    8. Restart if it was running
    #
    #  NOTE: This does NOT update instances.yaml, colmena.nix, or the
    #  NixOS host config. Run incus-sync pull after, and update the nix
    #  configs manually.
    # ══════════════════════════════════════════════════════════════
    do_rename() {
      # Build list of all containers for the picker
      mapfile -t CONTAINERS < <(incus list -c n --format csv)
      if [ ''${#CONTAINERS[@]} -eq 0 ]; then
        $GUM style --foreground 196 "No containers found."
        exit 1
      fi

      $GUM style --foreground 212 "Select container to rename:"
      OLD_NAME=$($GUM choose "''${CONTAINERS[@]}")

      NEW_NAME=$($GUM input --placeholder "Enter the new hostname")
      if [ -z "$NEW_NAME" ]; then exit 1; fi

      if [ "$OLD_NAME" = "$NEW_NAME" ]; then
        $GUM style --foreground 214 "Names are identical. Nothing to do."
        exit 0
      fi

      # Don't clobber an existing container
      if incus info "$NEW_NAME" >/dev/null 2>&1; then
        $GUM style --foreground 196 "Container $NEW_NAME already exists."
        exit 1
      fi

      # Check current state so we can stop/restart as needed
      STATE=$(incus query "/1.0/instances/$OLD_NAME" | $JQ -r '.status')
      WAS_RUNNING=false
      if [ "$STATE" = "Running" ]; then
        WAS_RUNNING=true
      fi

      # Check if this container has a nix-store device (most do, VMs might not)
      OLD_NIX_SOURCE=$(incus config device get "$OLD_NAME" nix-store source 2>/dev/null || true)
      HAS_NIX_STORE=false
      if [ -n "$OLD_NIX_SOURCE" ]; then
        HAS_NIX_STORE=true
      fi

      # --- Show plan and confirm ---
      echo ""
      $GUM style --foreground 86 --bold "Rename plan:"
      echo "  Container: $OLD_NAME → $NEW_NAME"
      if [ "$WAS_RUNNING" = true ]; then
        echo "  Status:    Running (will stop, rename, restart)"
      else
        echo "  Status:    Stopped"
      fi
      if [ "$HAS_NIX_STORE" = true ]; then
        echo "  Nix store: $NIX_HOST_MOUNT_BASE/$OLD_NAME → $NIX_HOST_MOUNT_BASE/$NEW_NAME"
        echo "  ZFS:       $NIX_PARENT_DATASET/$OLD_NAME → $NIX_PARENT_DATASET/$NEW_NAME"
      fi
      echo ""

      if ! $GUM confirm "Proceed with rename?"; then
        $GUM style --foreground 214 "Aborted."
        exit 0
      fi

      # --- Execute rename ---

      if [ "$WAS_RUNNING" = true ]; then
        echo "==> Stopping $OLD_NAME..."
        incus stop "$OLD_NAME"
      fi

      # Rename the Incus container itself
      echo "==> Renaming container $OLD_NAME → $NEW_NAME..."
      incus rename "$OLD_NAME" "$NEW_NAME"

      # Rename the ZFS dataset backing the nix store and update the
      # device source path so the container mounts the right location.
      if [ "$HAS_NIX_STORE" = true ]; then
        echo "==> Renaming ZFS dataset..."
        sudo zfs rename "$NIX_PARENT_DATASET/$OLD_NAME" "$NIX_PARENT_DATASET/$NEW_NAME"

        echo "==> Updating nix-store device source..."
        incus config device set "$NEW_NAME" nix-store source="$NIX_HOST_MOUNT_BASE/$NEW_NAME"
      fi

      if [ "$WAS_RUNNING" = true ]; then
        echo "==> Starting $NEW_NAME..."
        incus start "$NEW_NAME"
      fi

      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Successfully renamed $OLD_NAME → $NEW_NAME"
    }

    # ══════════════════════════════════════════════════════════════
    #  DELETE — destroy a container and optionally its nix store
    #
    #  Flow:
    #    1. Pick container from list
    #    2. Show what will be destroyed
    #    3. Optionally include the ZFS nix store dataset
    #    4. Double-confirm (defaults to No)
    #    5. Stop if running, delete container
    #    6. Destroy ZFS dataset if opted in
    #
    #  NOTE: This does NOT remove the instance from instances.yaml.
    #  Run incus-sync pull after to update the declarative config.
    # ══════════════════════════════════════════════════════════════
    do_delete() {
      # Build list of all containers for the picker
      mapfile -t CONTAINERS < <(incus list -c n --format csv)
      if [ ''${#CONTAINERS[@]} -eq 0 ]; then
        $GUM style --foreground 196 "No containers found."
        exit 1
      fi

      $GUM style --foreground 212 "Select container to delete:"
      TARGET=$($GUM choose "''${CONTAINERS[@]}")

      # Gather info for the plan display
      STATE=$(incus query "/1.0/instances/$TARGET" | $JQ -r '.status')

      NIX_SOURCE=$(incus config device get "$TARGET" nix-store source 2>/dev/null || true)
      HAS_NIX_STORE=false
      NIX_DATASET=""
      if [ -n "$NIX_SOURCE" ]; then
        HAS_NIX_STORE=true
        NIX_DATASET="$NIX_PARENT_DATASET/$TARGET"
      fi

      # --- Show plan ---
      echo ""
      $GUM style --foreground 196 --bold "DELETE plan:"
      echo "  Container: $TARGET"
      echo "  Status:    $STATE"
      if [ "$HAS_NIX_STORE" = true ]; then
        echo "  Nix store: $NIX_SOURCE (ZFS: $NIX_DATASET)"
      fi
      echo ""
      $GUM style --foreground 196 "This is DESTRUCTIVE and cannot be undone."

      # Ask about nix store separately — sometimes you want to keep it
      # (e.g. to recreate the container later with the same store).
      DESTROY_STORE=false
      if [ "$HAS_NIX_STORE" = true ]; then
        if $GUM confirm --default=No "Also destroy nix store dataset ($NIX_DATASET)?"; then
          DESTROY_STORE=true
        fi
      fi

      # Final confirmation — defaults to No for safety
      echo ""
      if ! $GUM confirm --default=No "Delete $TARGET? This cannot be undone."; then
        $GUM style --foreground 214 "Aborted."
        exit 0
      fi

      # --- Execute deletion ---

      if [ "$STATE" = "Running" ]; then
        echo "==> Stopping $TARGET..."
        incus stop "$TARGET"
      fi

      echo "==> Deleting container $TARGET..."
      incus delete "$TARGET"

      # Recursively destroy the ZFS dataset (includes any snapshots)
      if [ "$DESTROY_STORE" = true ]; then
        echo "==> Destroying ZFS dataset $NIX_DATASET..."
        sudo zfs destroy -r "$NIX_DATASET"
      fi

      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Deleted $TARGET"
    }

    # ── Dispatch to selected action ───────────────────────────────
    case "$ACTION" in
      create) do_create ;;
      rename) do_rename ;;
      delete) do_delete ;;
    esac
  '';
in
{
  environment.systemPackages = [
    pkgs.gum
    pkgs.pv
    pkgs.figlet
    pkgs.jq
    nixosFactoryScript
  ];
}

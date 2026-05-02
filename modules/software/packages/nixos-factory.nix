{ config, pkgs, ... }:

let
  nixosFactoryScript = pkgs.writeShellScriptBin "nixos-factory" ''
    set -e

    GUM="${pkgs.gum}/bin/gum"
    FIGLET="${pkgs.figlet}/bin/figlet"
    PV="${pkgs.pv}/bin/pv"
    JQ="${pkgs.jq}/bin/jq"

    # --- Configuration ---
    IMAGE_ALIAS="nixos-base-image"
    PROFILE="nixos-lxc"
    ROOT_POOLS=("rpool" "downloadHDD" "VMDisks")

    NIX_TEMPLATE_SNAPSHOT="rpool/VMDisks/nix-templates/nixos-base-nix@ready"
    NIX_PARENT_DATASET="downloadHDD/nix-stores"
    NIX_HOST_MOUNT_BASE="/mnt/nix-stores"

    UID_GID="100000:100000"

    NIX_CONFIG="/mnt/zpool/code/nix-config"
    INSTANCES_YAML="$NIX_CONFIG/hosts/server-nix/system/incus/instances.yaml"
    COLMENA_NIX="$NIX_CONFIG/flake-outputs/colmena.nix"

    # --- Splash ---
    clear
    $GUM style --foreground 86 --border-foreground 86 --border double \
      --align center --width 50 "$($FIGLET -f small "NIXOS FACTORY")"

    ACTION=$($GUM choose "create" "rename" "delete")

    # ========================================
    #  CREATE
    # ========================================
    do_create() {
      HOSTNAME=$($GUM input --placeholder "Enter the new container hostname")
      if [ -z "$HOSTNAME" ]; then exit 1; fi

      # Verify NixOS config exists in colmena
      if ! grep -q "\"$HOSTNAME\"" "$COLMENA_NIX"; then
        $GUM style --foreground 196 --bold "No colmena config found for $HOSTNAME"
        $GUM style --foreground 214 \
          "Create a NixOS config at hosts/server-nix/LXCs/ and add a colmena entry first."
        exit 1
      fi

      if incus info "$HOSTNAME" >/dev/null 2>&1; then
        $GUM style --foreground 196 "Container $HOSTNAME already exists in Incus."
        exit 1
      fi

      $GUM style --foreground 212 "Select target root storage pool:"
      SELECTED_POOL=$($GUM choose "''${ROOT_POOLS[@]}")

      MAC_ADDR=$($GUM input --placeholder "MAC address (leave blank to auto-generate)")
      if [ -z "$MAC_ADDR" ]; then
        MAC_ADDR=$(printf '02:%02X:%02X:%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
        $GUM style --foreground 212 "Generated MAC: $MAC_ADDR"
      fi

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

      echo "==> Initializing root FS on $SELECTED_POOL..."
      incus init "$IMAGE_ALIAS" "$HOSTNAME" -p "$PROFILE" -s "$SELECTED_POOL"

      DATASET_NAME="''${NIX_TEMPLATE_SNAPSHOT%@*}"
      SIZE=$(sudo zfs list -H -p -o referenced "$DATASET_NAME")

      echo "==> Replicating nix store to $NIX_PARENT_DATASET/$HOSTNAME..."
      sudo zfs send "$NIX_TEMPLATE_SNAPSHOT" | $PV -p -s "$SIZE" | sudo zfs receive "$NIX_PARENT_DATASET/$HOSTNAME"

      $GUM spin --spinner pulse --title "Configuring devices..." -- bash -c "
        sudo chown -R $UID_GID $NIX_HOST_MOUNT_BASE/$HOSTNAME

        incus config device add $HOSTNAME nix-store disk source=$NIX_HOST_MOUNT_BASE/$HOSTNAME path=/nix

        if incus config device show $HOSTNAME | grep -q '^eth0:'; then
          incus config device set $HOSTNAME eth0 hwaddr=$MAC_ADDR
        else
          incus config device add $HOSTNAME eth0 nic nictype=bridged parent=br0 hwaddr=$MAC_ADDR
        fi
      "

      # Add to instances.yaml
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

      echo "==> Starting $HOSTNAME..."
      incus start "$HOSTNAME"

      echo "==> Waiting for $HOSTNAME to get network..."
      for i in $(seq 1 30); do
        if incus exec "$HOSTNAME" -- ping -c1 -W1 build-nix.lan >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      echo "==> Deploying NixOS config via build-nix..."
      ssh build-nix.lan "deploy $HOSTNAME"

      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Successfully created and deployed $HOSTNAME
    Pool:  $SELECTED_POOL
    MAC:   $MAC_ADDR
    Store: $NIX_HOST_MOUNT_BASE/$HOSTNAME"
    }

    # ========================================
    #  RENAME
    # ========================================
    do_rename() {
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

      if incus info "$NEW_NAME" >/dev/null 2>&1; then
        $GUM style --foreground 196 "Container $NEW_NAME already exists."
        exit 1
      fi

      STATE=$(incus query "/1.0/instances/$OLD_NAME" | $JQ -r '.status')
      WAS_RUNNING=false
      if [ "$STATE" = "Running" ]; then
        WAS_RUNNING=true
      fi

      OLD_NIX_SOURCE=$(incus config device get "$OLD_NAME" nix-store source 2>/dev/null || true)
      HAS_NIX_STORE=false
      if [ -n "$OLD_NIX_SOURCE" ]; then
        HAS_NIX_STORE=true
      fi

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

      if [ "$WAS_RUNNING" = true ]; then
        echo "==> Stopping $OLD_NAME..."
        incus stop "$OLD_NAME"
      fi

      echo "==> Renaming container $OLD_NAME → $NEW_NAME..."
      incus rename "$OLD_NAME" "$NEW_NAME"

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

    # ========================================
    #  DELETE
    # ========================================
    do_delete() {
      mapfile -t CONTAINERS < <(incus list -c n --format csv)
      if [ ''${#CONTAINERS[@]} -eq 0 ]; then
        $GUM style --foreground 196 "No containers found."
        exit 1
      fi

      $GUM style --foreground 212 "Select container to delete:"
      TARGET=$($GUM choose "''${CONTAINERS[@]}")

      STATE=$(incus query "/1.0/instances/$TARGET" | $JQ -r '.status')

      NIX_SOURCE=$(incus config device get "$TARGET" nix-store source 2>/dev/null || true)
      HAS_NIX_STORE=false
      NIX_DATASET=""
      if [ -n "$NIX_SOURCE" ]; then
        HAS_NIX_STORE=true
        NIX_DATASET="$NIX_PARENT_DATASET/$TARGET"
      fi

      echo ""
      $GUM style --foreground 196 --bold "DELETE plan:"
      echo "  Container: $TARGET"
      echo "  Status:    $STATE"
      if [ "$HAS_NIX_STORE" = true ]; then
        echo "  Nix store: $NIX_SOURCE (ZFS: $NIX_DATASET)"
      fi
      echo ""
      $GUM style --foreground 196 "This is DESTRUCTIVE and cannot be undone."

      DESTROY_STORE=false
      if [ "$HAS_NIX_STORE" = true ]; then
        if $GUM confirm --default=No "Also destroy nix store dataset ($NIX_DATASET)?"; then
          DESTROY_STORE=true
        fi
      fi

      echo ""
      if ! $GUM confirm --default=No "Delete $TARGET? This cannot be undone."; then
        $GUM style --foreground 214 "Aborted."
        exit 0
      fi

      if [ "$STATE" = "Running" ]; then
        echo "==> Stopping $TARGET..."
        incus stop "$TARGET"
      fi

      echo "==> Deleting container $TARGET..."
      incus delete "$TARGET"

      if [ "$DESTROY_STORE" = true ]; then
        echo "==> Destroying ZFS dataset $NIX_DATASET..."
        sudo zfs destroy -r "$NIX_DATASET"
      fi

      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Deleted $TARGET"
    }

    # --- Dispatch ---
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

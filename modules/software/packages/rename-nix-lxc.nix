{ config, pkgs, ... }:

let
  renameNixosScript = pkgs.writeShellScriptBin "rename-nixos" ''
    set -e

    GUM="${pkgs.gum}/bin/gum"
    FIGLET="${pkgs.figlet}/bin/figlet"
    JQ="${pkgs.jq}/bin/jq"

    NIX_PARENT_DATASET="downloadHDD/nix-stores"
    NIX_HOST_MOUNT_BASE="/mnt/nix-stores"

    clear
    $GUM style --foreground 86 --border-foreground 86 --border double \
      --align center --width 50 "$($FIGLET -f small "NIXOS RENAME")"

    # Pick container
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

    # Check new name doesn't already exist
    if incus info "$NEW_NAME" >/dev/null 2>&1; then
      $GUM style --foreground 196 "Container $NEW_NAME already exists."
      exit 1
    fi

    # Check if running
    STATE=$(incus query "/1.0/instances/$OLD_NAME" | $JQ -r '.status')
    WAS_RUNNING=false
    if [ "$STATE" = "Running" ]; then
      WAS_RUNNING=true
    fi

    # Check nix-store device
    OLD_NIX_SOURCE=$(incus config device get "$OLD_NAME" nix-store source 2>/dev/null || true)
    HAS_NIX_STORE=false
    if [ -n "$OLD_NIX_SOURCE" ]; then
      HAS_NIX_STORE=true
    fi

    # Show plan
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

    # Stop if running
    if [ "$WAS_RUNNING" = true ]; then
      echo "==> Stopping $OLD_NAME..."
      incus stop "$OLD_NAME"
    fi

    # Rename container
    echo "==> Renaming container $OLD_NAME → $NEW_NAME..."
    incus rename "$OLD_NAME" "$NEW_NAME"

    # Rename nix store
    if [ "$HAS_NIX_STORE" = true ]; then
      echo "==> Renaming ZFS dataset $NIX_PARENT_DATASET/$OLD_NAME → $NEW_NAME..."
      sudo zfs rename "$NIX_PARENT_DATASET/$OLD_NAME" "$NIX_PARENT_DATASET/$NEW_NAME"

      echo "==> Updating nix-store device source..."
      incus config device set "$NEW_NAME" nix-store source="$NIX_HOST_MOUNT_BASE/$NEW_NAME"
    fi

    # Restart if was running
    if [ "$WAS_RUNNING" = true ]; then
      echo "==> Starting $NEW_NAME..."
      incus start "$NEW_NAME"
    fi

    $GUM style --foreground 82 --border rounded --padding "1 2" \
      "Successfully renamed $OLD_NAME → $NEW_NAME"
  '';
in
{
  environment.systemPackages = [
    pkgs.gum
    pkgs.figlet
    pkgs.jq
    renameNixosScript
  ];
}

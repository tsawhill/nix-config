{ pkgs, ... }:

let
  pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  knownHostsManager = pkgs.writeText "known-hosts-manager.py" ''
    import sys

    SECTION_BY_TAG = {
        "self": "# Core hosts",
        "daily": "# Daily services",
        "weekly": "# Weekly services",
        "monthly": "# Monthly services",
    }

    def read_lines(path):
        try:
            with open(path) as f:
                return f.readlines()
        except FileNotFoundError:
            return []

    def write_lines(path, lines):
        while lines and not lines[-1].strip():
            lines.pop()
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        with open(path, "w") as f:
            f.writelines(lines)

    def without_host(lines, host):
        result = []
        for line in lines:
            stripped = line.strip()
            if stripped and not stripped.startswith("#") and stripped.split()[0] == host:
                continue
            result.append(line)
        return result

    def section_bounds(lines, header):
        try:
            start = lines.index(header + "\n")
        except ValueError:
            if lines and lines[-1].strip():
                lines.append("\n")
            lines.append(header + "\n")
            return len(lines), len(lines)

        end = len(lines)
        for idx in range(start + 1, len(lines)):
            if lines[idx].startswith("# "):
                end = idx
                break
        return start + 1, end

    def upsert(path, host, key_line, tag):
        header = SECTION_BY_TAG.get(tag, "# Factory-managed hosts")
        lines = without_host(read_lines(path), host)
        start, end = section_bounds(lines, header)
        before = lines[:start]
        section = [
            line for line in lines[start:end]
            if line.strip() and not line.startswith("#")
        ]
        after = lines[end:]
        while after and not after[0].strip():
            after.pop(0)

        section.append(key_line.rstrip() + "\n")
        section = sorted(section, key=lambda line: line.split()[0])

        new_lines = before + section
        if after:
            new_lines.append("\n")
        new_lines.extend(after)
        write_lines(path, new_lines)

    def remove(path, host):
        lines = read_lines(path)
        new_lines = without_host(lines, host)
        if new_lines != lines:
            write_lines(path, new_lines)

    action = sys.argv[1]
    if action == "upsert":
        upsert(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif action == "remove":
        remove(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(f"unknown action: {action}")
  '';

  colmenaTagReader = pkgs.writeText "colmena-tag-reader.py" ''
    import re
    import sys

    path, host = sys.argv[1], sys.argv[2]
    with open(path) as f:
        lines = f.readlines()

    for idx, line in enumerate(lines):
        if f'"{host}"' not in line or "=" not in line:
            continue

        block = "".join(lines[idx:idx + 6])
        match = re.search(r'mk(?:Unstable)?Host\s+"([^"]+)"', block)
        if match is None:
            match = re.search(r'mkPiHost\s+"([^"]+)"', block)
        if match is not None:
            print(match.group(1))
            raise SystemExit(0)

    print("weekly")
  '';

  sopsYamlManager = pkgs.writeText "sops-yaml-manager.py" ''
    import sys

    SECTION_BY_TAG = {
        "self": "  # Core hosts",
        "daily": "  # Daily services",
        "weekly": "  # Weekly services",
        "monthly": "  # Monthly services",
    }

    def read_lines(path):
        with open(path) as f:
            return f.readlines()

    def write_lines(path, lines):
        while lines and not lines[-1].strip():
            lines.pop()
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        with open(path, "w") as f:
            f.writelines(lines)

    def without_key(lines, host):
        result = []
        needle = f"  - &{host} "
        for line in lines:
            if line.startswith(needle):
                continue
            result.append(line)
        return result

    def keys_bounds(lines):
        try:
            keys_start = lines.index("keys:\n") + 1
        except ValueError:
            raise SystemExit("missing top-level keys section")

        try:
            creation_start = lines.index("creation_rules:\n")
        except ValueError:
            raise SystemExit("missing top-level creation_rules section")

        return keys_start, creation_start

    def section_bounds(lines, keys_start, creation_start, header):
        for idx in range(keys_start, creation_start):
            if lines[idx] == header + "\n":
                start = idx + 1
                end = creation_start
                for section_end in range(start, creation_start):
                    if lines[section_end].lstrip().startswith("# "):
                        end = section_end
                        break
                return start, end

        insert_at = creation_start
        block = []
        if insert_at > keys_start and lines[insert_at - 1].strip():
            block.append("\n")
        block.append(header + "\n")
        lines[insert_at:insert_at] = block
        return insert_at + len(block), insert_at + len(block)

    def upsert(path, host, recipient, tag):
        header = SECTION_BY_TAG.get(tag, "  # Factory-managed hosts")
        lines = without_key(read_lines(path), host)
        keys_start, creation_start = keys_bounds(lines)
        start, end = section_bounds(lines, keys_start, creation_start, header)
        before = lines[:start]
        section = [
            line for line in lines[start:end]
            if line.strip() and not line.startswith("#")
        ]
        after = lines[end:]
        while after and not after[0].strip():
            after.pop(0)

        section.append(f"  - &{host} {recipient}\n")
        section = sorted(section, key=lambda line: line.split()[1].removeprefix("&"))

        new_lines = before + section
        if after:
            new_lines.append("\n")
        new_lines.extend(after)
        write_lines(path, new_lines)

    def remove(path, host):
        lines = read_lines(path)
        new_lines = without_key(lines, host)
        if new_lines != lines:
            write_lines(path, new_lines)

    action = sys.argv[1]
    if action == "upsert":
        upsert(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif action == "remove":
        remove(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(f"unknown action: {action}")
  '';

  topologyManager = pkgs.writeText "topology-manager.py" ''
    import ipaddress
    import re
    import sys

    def read_lines(path):
        with open(path) as f:
            return f.readlines()

    def write_lines(path, lines):
        with open(path, "w") as f:
            f.writelines(lines)

    def hosts_bounds(lines):
        try:
            start = lines.index("  hosts = {\n") + 1
        except ValueError:
            raise SystemExit("missing topology hosts section")

        for end in range(start, len(lines)):
            if lines[end] == "  };\n":
                return start, end
        raise SystemExit("unterminated topology hosts section")

    def host_pattern(host):
        return re.compile(rf"^    {re.escape(host)}(?:\.[^=\s]+)?\s*=")

    def add(path, host, address, mac):
        try:
            ipaddress.IPv4Address(address)
        except ipaddress.AddressValueError:
            raise SystemExit(f"invalid IPv4 address: {address}")

        if re.fullmatch(r"(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}", mac) is None:
            raise SystemExit(f"invalid MAC address: {mac}")

        lines = read_lines(path)
        start, end = hosts_bounds(lines)
        host_lines = lines[start:end]

        if any(host_pattern(host).match(line) for line in host_lines):
            raise SystemExit(f"topology host already exists: {host}")

        ip_needle = re.compile(rf'\bip\s*=\s*"{re.escape(address)}";')
        if any(ip_needle.search(line) for line in host_lines):
            raise SystemExit(f"topology IP already exists: {address}")

        mac_needle = re.compile(rf'\bmac\s*=\s*"{re.escape(mac)}";', re.IGNORECASE)
        if any(mac_needle.search(line) for line in host_lines):
            raise SystemExit(f"topology MAC already exists: {mac}")

        block = [
            f"    {host} = {{\n",
            "      lan = {\n",
            f'        ip = "{address}";\n',
            f'        mac = "{mac.lower()}";\n',
            "      };\n",
            "      dns.enable = true;\n",
            "    };\n",
        ]
        lines[end:end] = block
        write_lines(path, lines)

    def remove(path, host):
        lines = read_lines(path)
        start, end = hosts_bounds(lines)
        entry_start = None
        opening = f"    {host} = {{\n"

        for idx in range(start, end):
            if lines[idx] == opening:
                entry_start = idx
                break

        if entry_start is None:
            return

        for entry_end in range(entry_start + 1, end):
            if lines[entry_end] == "    };\n":
                del lines[entry_start:entry_end + 1]
                write_lines(path, lines)
                return

        raise SystemExit(f"unterminated topology entry: {host}")

    action = sys.argv[1]
    if action == "add":
        add(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif action == "remove":
        remove(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(f"unknown action: {action}")
  '';

  # Helper: remove a top-level YAML block by key name from a file.
  # Operates on raw lines to preserve exact formatting.
  removeYamlBlock = pkgs.writeShellScript "remove-yaml-block" ''
    set -euo pipefail
    TARGET="$1"
    FILE="$2"
    ${pythonWithYaml}/bin/python3 -c "
import sys
target = sys.argv[1]
with open(sys.argv[2]) as f:
    lines = f.readlines()
result = []
skip = False
for line in lines:
    stripped = line.rstrip()
    # Match the start of the target block (top-level key)
    if not skip and stripped == target + ':':
        skip = True
        # Remove preceding blank line
        if result and not result[-1].strip():
            result.pop()
        continue
    # End of block: non-indented non-blank line
    if skip and stripped and not line[0].isspace():
        skip = False
    if skip:
        continue
    result.append(line)
# Remove trailing blank lines
while result and not result[-1].strip():
    result.pop()
result.append(chr(10))  # ensure single trailing newline
with open(sys.argv[2], 'w') as f:
    f.writelines(result)
" "$TARGET" "$FILE"
  '';

  nixosFactoryScript = pkgs.writeShellScriptBin "nixos-factory" ''
    set -e

    # --- Tool paths (pinned to nix store) ---
    GUM="${pkgs.gum}/bin/gum"
    FIGLET="${pkgs.figlet}/bin/figlet"
    JQ="${pkgs.jq}/bin/jq"
    SSH="${pkgs.openssh}/bin/ssh"

    # Incus and ZFS live on server-nix. The factory itself runs on build-nix,
    # whose root SSH key is authorized on server-nix.
    SERVER_HOST="root@server-nix.lan"

    # --- Incus / ZFS defaults (on server-nix) ---
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

    # The repo is bind-mounted from server-nix into build-nix, so local edits
    # here are immediately visible to both hosts.
    NIX_CONFIG="/mnt/zpool/code/nix-config"
    INSTANCES_YAML="$NIX_CONFIG/hosts/server-nix/system/incus/instances.yaml"
    COLMENA_NIX="$NIX_CONFIG/flake-outputs/colmena.nix"
    TOPOLOGY_NIX="$NIX_CONFIG/modules/network/topology.nix"
    KNOWN_HOSTS_FILE="$NIX_CONFIG/modules/ssh/known_hosts"
    SOPS_YAML="$NIX_CONFIG/.sops.yaml"

    server_cmd() {
      "$SSH" \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        "$SERVER_HOST" \
        "$@"
    }

    require_server() {
      if ! server_cmd incus version >/dev/null 2>&1; then
        $GUM style --foreground 196 --bold \
          "Cannot run Incus over SSH on $SERVER_HOST"
        $GUM style --foreground 214 \
          "Check build-nix's root SSH key and the server-nix host key, then retry."
        exit 1
      fi
    }

    validate_hostname() {
      if [[ ! "$1" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
        $GUM style --foreground 196 --bold "Invalid hostname: $1"
        exit 1
      fi
    }

    validate_ipv4() {
      if ! ${pythonWithYaml}/bin/python3 -c \
        'import ipaddress, sys; ipaddress.IPv4Address(sys.argv[1])' "$1"
      then
        $GUM style --foreground 196 --bold "Invalid IPv4 address: $1"
        exit 1
      fi
    }

    validate_mac() {
      if [[ ! "$1" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
        $GUM style --foreground 196 --bold "Invalid MAC address: $1"
        exit 1
      fi
    }

    colmena_tag_for_host() {
      ${pythonWithYaml}/bin/python3 ${colmenaTagReader} "$COLMENA_NIX" "$1"
    }

    host_key_line() {
      host="$1"
      host_lan="$host.lan"

      server_cmd incus exec "$host" -- ssh-keygen -A >/dev/null 2>&1 || true
      public_key=$(server_cmd incus exec "$host" -- \
        cat /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null \
        | grep -E "^ssh-ed25519[[:space:]]" \
        | head -n1 || true)

      if [ -n "$public_key" ]; then
        printf '%s %s\n' "$host_lan" "$public_key"
        return 0
      fi

      ${pkgs.openssh}/bin/ssh-keyscan -T 10 -t ed25519 "$host_lan" 2>/dev/null \
        | grep -E "^$host_lan[[:space:]]+ssh-ed25519[[:space:]]" \
        | head -n1 || true
    }

    add_known_host() {
      host="$1"
      host_lan="$host.lan"
      tag=$(colmena_tag_for_host "$host")

      key_line=$(host_key_line "$host")

      if [ -z "$key_line" ]; then
        $GUM style --foreground 196 --bold "Could not read or scan Ed25519 host key for $host_lan"
        return 1
      fi

      ${pythonWithYaml}/bin/python3 ${knownHostsManager} upsert \
        "$KNOWN_HOSTS_FILE" "$host_lan" "$key_line" "$tag"
      ${pkgs.openssh}/bin/ssh-keygen -l -f "$KNOWN_HOSTS_FILE" >/dev/null
      echo "==> Added $host_lan to known_hosts ($tag)"
    }

    remove_known_host() {
      host="$1"
      ${pythonWithYaml}/bin/python3 ${knownHostsManager} remove \
        "$KNOWN_HOSTS_FILE" "$host.lan"
      ${pkgs.openssh}/bin/ssh-keygen -l -f "$KNOWN_HOSTS_FILE" >/dev/null
      echo "==> Removed $host.lan from known_hosts"
    }

    add_sops_age_key() {
      host="$1"
      host_lan="$host.lan"
      tag=$(colmena_tag_for_host "$host")
      key_line=$(host_key_line "$host")

      if [ -z "$key_line" ]; then
        $GUM style --foreground 196 --bold "Could not read or scan Ed25519 host key for $host_lan"
        return 1
      fi

      public_key=''${key_line#"$host_lan "}
      age_recipient=$(printf '%s\n' "$public_key" \
        | ${pkgs.ssh-to-age}/bin/ssh-to-age -i - \
        | head -n1)

      if [[ ! "$age_recipient" =~ ^age1 ]]; then
        $GUM style --foreground 196 --bold "Could not derive age recipient for $host"
        return 1
      fi

      ${pythonWithYaml}/bin/python3 ${sopsYamlManager} upsert \
        "$SOPS_YAML" "$host" "$age_recipient" "$tag"
      echo "==> Added $host age recipient to .sops.yaml ($tag)"
    }

    remove_sops_age_key() {
      host="$1"
      ${pythonWithYaml}/bin/python3 ${sopsYamlManager} remove \
        "$SOPS_YAML" "$host"
      echo "==> Removed $host age recipient from .sops.yaml"
    }

    deploy_build_nix() {
      deploy build-nix
    }

    deploy_host() {
      host="$1"
      deploy "$host"
    }

    deploy_adguard() {
      deploy adguard-nix || return
      echo "==> Waiting 30 seconds for AdGuard DNS to restart..."
      sleep 30
    }

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
    #    1. Prompt for hostname and optional topology/DNS management
    #    2. Verify a NixOS / colmena config already exists for it
    #    3. Collect IP, storage pool, and MAC address
    #    4. Show plan and confirm
    #    5. Optionally add topology and deploy AdGuard
    #    6. Create the container and nix store on server-nix over SSH
    #    7. Append the instance to instances.yaml
    #    8. Start the container and verify its expected DHCP address
    #    9. Trust the new host key, add its age recipient, and deploy build-nix
    #   10. Deploy the new host from build-nix
    # ══════════════════════════════════════════════════════════════
    do_create() {
      require_server

      HOSTNAME=$($GUM input --placeholder "Enter the new container hostname")
      if [ -z "$HOSTNAME" ]; then exit 1; fi
      validate_hostname "$HOSTNAME"

      MANAGE_TOPOLOGY=false
      if $GUM confirm "Add $HOSTNAME to topology and deploy AdGuard DNS?"; then
        MANAGE_TOPOLOGY=true
      fi

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
      if server_cmd incus info "$HOSTNAME" >/dev/null 2>&1; then
        $GUM style --foreground 196 "Container $HOSTNAME already exists in Incus."
        exit 1
      fi

      # --- Collect parameters ---

      IP_ADDRESS=""
      if [ "$MANAGE_TOPOLOGY" = true ]; then
        IP_ADDRESS=$($GUM input --placeholder "LAN IPv4 address (for example 10.73.73.31)")
        if [ -z "$IP_ADDRESS" ]; then exit 1; fi
        validate_ipv4 "$IP_ADDRESS"
      fi

      $GUM style --foreground 212 "Select target root storage pool:"
      SELECTED_POOL=$($GUM choose "''${ROOT_POOLS[@]}")

      # MAC can be manually specified (e.g. to match a DHCP reservation)
      # or auto-generated with a locally-administered prefix (02:xx:xx:xx:xx:xx).
      MAC_ADDR=$($GUM input --placeholder "MAC address (leave blank to auto-generate)")
      if [ -z "$MAC_ADDR" ]; then
        MAC_ADDR=$(printf '02:%02X:%02X:%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
        $GUM style --foreground 212 "Generated MAC: $MAC_ADDR"
      fi
      validate_mac "$MAC_ADDR"
      MAC_ADDR=$(printf '%s' "$MAC_ADDR" | tr '[:upper:]' '[:lower:]')

      # --- Show plan and confirm ---
      echo ""
      $GUM style --foreground 86 --bold "Create plan:"
      echo "  Hostname:  $HOSTNAME"
      echo "  Pool:      $SELECTED_POOL"
      echo "  MAC:       $MAC_ADDR"
      echo "  Store:     $NIX_HOST_MOUNT_BASE/$HOSTNAME"
      echo "  YAML:      $INSTANCES_YAML (will be updated)"
      if [ "$MANAGE_TOPOLOGY" = true ]; then
        echo "  Topology:  $HOSTNAME.lan → $IP_ADDRESS"
        echo "  DNS:       deploy adguard-nix"
      else
        echo "  Topology:  unchanged"
      fi
      echo "  Incus:     SSH to $SERVER_HOST"
      echo "  Deploy:    deploy $HOSTNAME"
      echo ""

      if ! $GUM confirm "Create container?"; then
        $GUM style --foreground 214 "Aborted."
        exit 0
      fi

      TOPOLOGY_ADDED=false
      ADGUARD_DEPLOY_ATTEMPTED=false
      CONTAINER_CREATED=false
      DATASET_CREATED=false
      INSTANCE_ADDED=false
      KNOWN_HOST_ADDED=false
      SOPS_KEY_ADDED=false
      TRUST_DEPLOY_ATTEMPTED=false

      rollback_create() {
        reason="$1"
        trap - ERR
        set +e

        $GUM style --foreground 196 --bold "$reason — rolling back..."

        if [ "$CONTAINER_CREATED" = true ] \
          && server_cmd incus info "$HOSTNAME" >/dev/null 2>&1
        then
          echo "==> Stopping and deleting $HOSTNAME on server-nix..."
          server_cmd incus stop "$HOSTNAME" --force >/dev/null 2>&1 || true
          server_cmd incus delete "$HOSTNAME" >/dev/null 2>&1 || true
        fi

        if [ "$DATASET_CREATED" = true ] \
          && server_cmd zfs list "$NIX_PARENT_DATASET/$HOSTNAME" >/dev/null 2>&1
        then
          echo "==> Destroying ZFS dataset $NIX_PARENT_DATASET/$HOSTNAME..."
          server_cmd zfs destroy -r "$NIX_PARENT_DATASET/$HOSTNAME" || true
        fi

        if [ "$INSTANCE_ADDED" = true ]; then
          echo "==> Removing $HOSTNAME from instances.yaml..."
          ${removeYamlBlock} "$HOSTNAME" "$INSTANCES_YAML" || true
        fi

        if [ "$KNOWN_HOST_ADDED" = true ]; then
          remove_known_host "$HOSTNAME" || true
        fi
        if [ "$SOPS_KEY_ADDED" = true ]; then
          remove_sops_age_key "$HOSTNAME" || true
        fi
        if [ "$TRUST_DEPLOY_ATTEMPTED" = true ]; then
          deploy_build_nix || true
        fi

        if [ "$TOPOLOGY_ADDED" = true ]; then
          echo "==> Removing $HOSTNAME from topology.nix..."
          ${pythonWithYaml}/bin/python3 ${topologyManager} \
            remove "$TOPOLOGY_NIX" "$HOSTNAME" || true
        fi
        if [ "$ADGUARD_DEPLOY_ATTEMPTED" = true ]; then
          echo "==> Restoring AdGuard DNS..."
          deploy_adguard || true
        fi

        $GUM style --foreground 196 --border rounded --padding "1 2" \
          "Create aborted. All factory changes were rolled back."
        exit 1
      }

      trap 'rollback_create "Unexpected create failure"' ERR

      # --- Step 1: Add topology and apply DNS ---
      if [ "$MANAGE_TOPOLOGY" = true ]; then
        echo "==> Adding $HOSTNAME to topology.nix..."
        if ! ${pythonWithYaml}/bin/python3 ${topologyManager} \
          add "$TOPOLOGY_NIX" "$HOSTNAME" "$IP_ADDRESS" "$MAC_ADDR"
        then
          rollback_create "Topology update failed"
        fi
        TOPOLOGY_ADDED=true

        echo "==> Deploying AdGuard DNS..."
        ADGUARD_DEPLOY_ATTEMPTED=true
        if ! deploy_adguard; then
          rollback_create "AdGuard deploy failed"
        fi
      fi

      # --- Step 2: Create the Incus container on server-nix ---
      # Uses the base NixOS image and the nixos-lxc profile for defaults
      # (2 CPU, 2GiB RAM, nesting, idmap, bridged networking).
      echo "==> Initializing root FS on $SELECTED_POOL..."
      if ! server_cmd incus init "$IMAGE_ALIAS" "$HOSTNAME" \
        -p "$PROFILE" -s "$SELECTED_POOL"
      then
        rollback_create "Incus initialization failed"
      fi
      CONTAINER_CREATED=true

      # --- Step 3: Clone the template nix store ---
      # ZFS send/receive copies the pre-built /nix from the template snapshot
      # into a new dataset for this container. Both ends stay on server-nix.
      echo "==> Replicating nix store to $NIX_PARENT_DATASET/$HOSTNAME..."
      if ! server_cmd \
        "zfs send $NIX_TEMPLATE_SNAPSHOT | zfs receive $NIX_PARENT_DATASET/$HOSTNAME"
      then
        rollback_create "Nix store replication failed"
      fi
      DATASET_CREATED=true

      # --- Step 4: Wire up devices ---
      # - chown the nix store to the container's mapped UID/GID
      # - Attach the host-side nix store as a disk device at /nix
      # - Set or create the eth0 NIC with the chosen MAC address
      echo "==> Configuring container devices on server-nix..."
      server_cmd chown -R "$UID_GID" "$NIX_HOST_MOUNT_BASE/$HOSTNAME"
      server_cmd incus config device add "$HOSTNAME" nix-store disk \
        source="$NIX_HOST_MOUNT_BASE/$HOSTNAME" path=/nix

      if server_cmd incus config device show "$HOSTNAME" | grep -q '^eth0:'; then
        server_cmd incus config device set "$HOSTNAME" eth0 hwaddr="$MAC_ADDR"
      else
        server_cmd incus config device add "$HOSTNAME" eth0 nic \
          nictype=bridged parent=br0 hwaddr="$MAC_ADDR"
      fi

      # --- Step 5: Add to declarative config ---
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
      INSTANCE_ADDED=true

      # --- Step 6: Start and wait for network ---
      # The container boots with the base NixOS image. We need it to get a
      # DHCP lease and be reachable before we can deploy the real config.
      echo "==> Starting $HOSTNAME..."
      server_cmd incus start "$HOSTNAME"

      echo "==> Waiting for $HOSTNAME to get network..."
      NETWORK_READY=false
      for i in $(seq 1 30); do
        if server_cmd incus exec "$HOSTNAME" -- \
          ping -c1 -W1 build-nix.lan >/dev/null 2>&1
        then
          NETWORK_READY=true
          break
        fi
        sleep 1
      done

      if [ "$NETWORK_READY" = false ]; then
        rollback_create "Container did not acquire working network"
      fi

      if [ "$MANAGE_TOPOLOGY" = true ]; then
        if ! server_cmd incus query "/1.0/instances/$HOSTNAME/state" \
          | "$JQ" -e --arg ip "$IP_ADDRESS" \
            'any(.network.eth0.addresses[]?; .family == "inet" and .address == $ip)' \
            >/dev/null
        then
          $GUM style --foreground 214 \
            "Expected $IP_ADDRESS for MAC $MAC_ADDR. Check the OPNsense DHCP reservation."
          rollback_create "Container received the wrong IPv4 address"
        fi
      fi

      # --- Step 7: Trust the new host from build-nix before deployment ---
      # Colmena runs from build-nix. The new container's host key must be in
      # the repo-level known_hosts and applied to build-nix before build-nix
      # can SSH to the target non-interactively.
      echo "==> Adding $HOSTNAME.lan to known_hosts..."
      if ! add_known_host "$HOSTNAME"; then
        rollback_create "Host key scan failed"
      fi
      KNOWN_HOST_ADDED=true

      echo "==> Adding $HOSTNAME age recipient to .sops.yaml..."
      if ! add_sops_age_key "$HOSTNAME"; then
        rollback_create "SOPS age recipient setup failed"
      fi
      SOPS_KEY_ADDED=true

      echo "==> Deploying updated trust data to build-nix..."
      TRUST_DEPLOY_ATTEMPTED=true
      if ! deploy_build_nix; then
        rollback_create "build-nix deploy failed"
      fi

      # --- Step 8: Deploy NixOS config ---
      # Build the NixOS config locally and push it to the new container.
      # If the deploy fails, automatically roll back everything we just created
      # so the system is left in the same state as before the script ran.
      echo "==> Deploying NixOS config from build-nix..."
      if ! deploy_host "$HOSTNAME"; then
        rollback_create "Host deploy failed"
      fi

      trap - ERR
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
      require_server

      # Build list of all containers for the picker
      mapfile -t CONTAINERS < <(server_cmd incus list -c n --format csv)
      if [ ''${#CONTAINERS[@]} -eq 0 ]; then
        $GUM style --foreground 196 "No containers found."
        exit 1
      fi

      $GUM style --foreground 212 "Select container to rename:"
      OLD_NAME=$($GUM choose "''${CONTAINERS[@]}")

      NEW_NAME=$($GUM input --placeholder "Enter the new hostname")
      if [ -z "$NEW_NAME" ]; then exit 1; fi
      validate_hostname "$NEW_NAME"

      if [ "$OLD_NAME" = "$NEW_NAME" ]; then
        $GUM style --foreground 214 "Names are identical. Nothing to do."
        exit 0
      fi

      # Don't clobber an existing container
      if server_cmd incus info "$NEW_NAME" >/dev/null 2>&1; then
        $GUM style --foreground 196 "Container $NEW_NAME already exists."
        exit 1
      fi

      # Check current state so we can stop/restart as needed
      STATE=$(server_cmd incus query "/1.0/instances/$OLD_NAME" | $JQ -r '.status')
      WAS_RUNNING=false
      if [ "$STATE" = "Running" ]; then
        WAS_RUNNING=true
      fi

      # Check if this container has a nix-store device (most do, VMs might not)
      OLD_NIX_SOURCE=$(server_cmd incus config device get \
        "$OLD_NAME" nix-store source 2>/dev/null || true)
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
        server_cmd incus stop "$OLD_NAME"
      fi

      # Rename the Incus container itself
      echo "==> Renaming container $OLD_NAME → $NEW_NAME..."
      server_cmd incus rename "$OLD_NAME" "$NEW_NAME"

      # Rename the ZFS dataset backing the nix store and update the
      # device source path so the container mounts the right location.
      if [ "$HAS_NIX_STORE" = true ]; then
        echo "==> Renaming ZFS dataset..."
        server_cmd zfs rename \
          "$NIX_PARENT_DATASET/$OLD_NAME" "$NIX_PARENT_DATASET/$NEW_NAME"

        echo "==> Updating nix-store device source..."
        server_cmd incus config device set \
          "$NEW_NAME" nix-store source="$NIX_HOST_MOUNT_BASE/$NEW_NAME"
      fi

      if [ "$WAS_RUNNING" = true ]; then
        echo "==> Starting $NEW_NAME..."
        server_cmd incus start "$NEW_NAME"
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
    #    7. Remove instance from instances.yaml
    #    8. Remove global trust entries and deploy build-nix
    #
    # ══════════════════════════════════════════════════════════════
    do_delete() {
      require_server

      # Build list of all containers for the picker
      mapfile -t CONTAINERS < <(server_cmd incus list -c n --format csv)
      if [ ''${#CONTAINERS[@]} -eq 0 ]; then
        $GUM style --foreground 196 "No containers found."
        exit 1
      fi

      $GUM style --foreground 212 "Select container to delete:"
      TARGET=$($GUM choose "''${CONTAINERS[@]}")

      # Gather info for the plan display
      STATE=$(server_cmd incus query "/1.0/instances/$TARGET" | $JQ -r '.status')

      NIX_SOURCE=$(server_cmd incus config device get \
        "$TARGET" nix-store source 2>/dev/null || true)
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
        server_cmd incus stop "$TARGET"
      fi

      echo "==> Deleting container $TARGET..."
      server_cmd incus delete "$TARGET"

      # Recursively destroy the ZFS dataset (includes any snapshots)
      if [ "$DESTROY_STORE" = true ]; then
        echo "==> Destroying ZFS dataset $NIX_DATASET..."
        server_cmd zfs destroy -r "$NIX_DATASET"
      fi

      # Remove from instances.yaml so declarative config stays in sync
      if grep -q "^$TARGET:" "$INSTANCES_YAML" 2>/dev/null; then
        echo "==> Removing $TARGET from instances.yaml..."
        ${removeYamlBlock} "$TARGET" "$INSTANCES_YAML"
      fi

      echo "==> Removing $TARGET.lan from known_hosts..."
      remove_known_host "$TARGET"

      echo "==> Removing $TARGET age recipient from .sops.yaml..."
      remove_sops_age_key "$TARGET"

      echo "==> Deploying updated trust data to build-nix..."
      deploy_build_nix

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
    pkgs.figlet
    pkgs.jq
    nixosFactoryScript
  ];
}

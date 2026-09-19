{
  lib,
  networkTopology,
  pkgs,
  ...
}:

let
  pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  factoryTopology = lib.mapAttrs (_: host: {
    ip = host.lan.ip or null;
    mac = host.lan.mac or null;
    intermittent = host.incus.intermittent or false;
  }) networkTopology.hosts;
  factoryTopologyJson = pkgs.writeText "nixos-factory-topology.json" (
    builtins.toJSON factoryTopology
  );

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

        # monitoring.enable opts the host into Prometheus scraping; new hosts
        # are always-on LXCs, so they are monitored from the start.
        block = [
            f"    {host} = {{\n",
            "      lan = {\n",
            f'        ip = "{address}";\n',
            f'        mac = "{mac.lower()}";\n',
            "      };\n",
            "      dns.enable = true;\n",
            "      monitoring.enable = true;\n",
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

  instanceConfigReader = pkgs.writeText "instance-config-reader.py" ''
    import sys
    import yaml

    path, host, field = sys.argv[1:]
    with open(path) as config_file:
        instances = yaml.safe_load(config_file) or {}

    instance = instances.get(host)
    if instance is None:
        raise SystemExit(f"missing instance declaration: {host}")

    if field == "profiles":
        for profile in instance.get("profiles", []):
            print(profile)
    elif field in ("pool", "size"):
        print(instance.get("devices", {}).get("root", {}).get(field, ""))
    else:
        raise SystemExit(f"unknown instance field: {field}")
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
    SCP="${pkgs.openssh}/bin/scp"
    NIX="${pkgs.nix}/bin/nix"

    # Incus and ZFS live on server-nix. The factory itself runs on build-nix,
    # whose root SSH key is authorized on server-nix.
    SERVER_HOST="root@server-nix.lan"

    # --- Incus / ZFS defaults (on server-nix) ---
    IMAGE_ALIAS="barebones-nixos-allow-keys" # local image alias for base NixOS LXC
    PROFILE="nixos-lxc"                  # default profile applied to new containers

    # Template nix store snapshot — cloned into each new container so it has a
    # working /nix from the start (avoids a full download on first deploy).
    NIX_TEMPLATE_SNAPSHOT="rpool/VMDisks/nix-templates/nixos-base-nix@ready"
    NIX_TEMPLATE_SNAPSHOT_NAME="''${NIX_TEMPLATE_SNAPSHOT##*@}"
    NIX_TEMPLATE_DATASET="''${NIX_TEMPLATE_SNAPSHOT%@*}"

    # Flake attribute the base image and its nix store are both built from.
    TEMPLATE_ATTR="nixosConfigurations.lxc-template.config.system.build"

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
    TOPOLOGY_JSON="${factoryTopologyJson}"

    server_cmd() {
      "$SSH" \
        -n \
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
    ACTION=$($GUM choose "create" "rename" "delete" "template")

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
    #    7. Preserve or append the instance in instances.yaml
    #    8. Start the container and verify its expected DHCP address
    #    9. Trust the new host key, add its age recipient, and deploy build-nix
    #   10. Deploy the new host from build-nix
    # ══════════════════════════════════════════════════════════════
    do_create() {
      require_server

      if ! ROOT_POOLS_OUTPUT=$(server_cmd incus storage list --columns n --format csv); then
        $GUM style --foreground 196 --bold "Could not list Incus storage pools."
        exit 1
      fi

      ROOT_POOLS=()
      while IFS= read -r pool; do
        if [ -n "$pool" ]; then
          ROOT_POOLS+=("$pool")
        fi
      done <<< "$ROOT_POOLS_OUTPUT"

      if [ "''${#ROOT_POOLS[@]}" -eq 0 ]; then
        $GUM style --foreground 196 --bold "Incus did not report any storage pools."
        exit 1
      fi

      HOSTNAME=$($GUM input --placeholder "Enter the new container hostname")
      if [ -z "$HOSTNAME" ]; then exit 1; fi
      validate_hostname "$HOSTNAME"

      MANAGE_TOPOLOGY=false
      USE_EXISTING_TOPOLOGY=false
      VERIFY_TOPOLOGY=false
      INTERMITTENT=false
      IP_ADDRESS=""
      MAC_ADDR=""

      if $JQ -e --arg host "$HOSTNAME" 'has($host)' "$TOPOLOGY_JSON" >/dev/null; then
        IP_ADDRESS=$($JQ -r --arg host "$HOSTNAME" '.[$host].ip // empty' "$TOPOLOGY_JSON")
        MAC_ADDR=$($JQ -r --arg host "$HOSTNAME" '.[$host].mac // empty' "$TOPOLOGY_JSON")
        INTERMITTENT=$($JQ -r --arg host "$HOSTNAME" '.[$host].intermittent // false' "$TOPOLOGY_JSON")
        if [ -z "$IP_ADDRESS" ] || [ -z "$MAC_ADDR" ]; then
          $GUM style --foreground 196 --bold \
            "$HOSTNAME exists in topology but does not have both a LAN IP and MAC"
          exit 1
        fi
        USE_EXISTING_TOPOLOGY=true
        VERIFY_TOPOLOGY=true
        $GUM style --foreground 212 \
          "Using existing topology: $HOSTNAME.lan → $IP_ADDRESS ($MAC_ADDR)"
      elif $GUM confirm "Add $HOSTNAME to topology and deploy AdGuard DNS?"; then
        MANAGE_TOPOLOGY=true
        VERIFY_TOPOLOGY=true
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

      USE_EXISTING_INSTANCE=false
      if grep -q "^$HOSTNAME:$" "$INSTANCES_YAML"; then
        USE_EXISTING_INSTANCE=true
      fi

      # Don't clobber an existing container
      if server_cmd incus info "$HOSTNAME" >/dev/null 2>&1; then
        $GUM style --foreground 196 "Container $HOSTNAME already exists in Incus."
        exit 1
      fi

      # --- Collect parameters ---

      if [ "$MANAGE_TOPOLOGY" = true ]; then
        IP_ADDRESS=$($GUM input --placeholder "LAN IPv4 address (for example 10.73.73.31)")
        if [ -z "$IP_ADDRESS" ]; then exit 1; fi
        validate_ipv4 "$IP_ADDRESS"
      fi

      if [ "$USE_EXISTING_INSTANCE" = true ]; then
        SELECTED_POOL=$(${pythonWithYaml}/bin/python3 ${instanceConfigReader} \
          "$INSTANCES_YAML" "$HOSTNAME" pool)
      fi
      if [ -z "''${SELECTED_POOL:-}" ]; then
        $GUM style --foreground 212 "Select target root storage pool:"
        SELECTED_POOL=$($GUM choose "''${ROOT_POOLS[@]}")
      fi

      # MAC can be manually specified (e.g. to match a DHCP reservation)
      # or auto-generated with a locally-administered prefix (02:xx:xx:xx:xx:xx).
      if [ "$USE_EXISTING_TOPOLOGY" = false ]; then
        MAC_ADDR=$($GUM input --placeholder "MAC address (leave blank to auto-generate)")
        if [ -z "$MAC_ADDR" ]; then
          MAC_ADDR=$(printf '02:%02X:%02X:%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
          $GUM style --foreground 212 "Generated MAC: $MAC_ADDR"
        fi
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
      if [ "$USE_EXISTING_INSTANCE" = true ]; then
        echo "  YAML:      $INSTANCES_YAML (existing declaration)"
      else
        echo "  YAML:      $INSTANCES_YAML (will be updated)"
      fi
      if [ "$USE_EXISTING_TOPOLOGY" = true ]; then
        echo "  Topology:  existing ($HOSTNAME.lan → $IP_ADDRESS)"
        echo "  DNS:       unchanged"
      elif [ "$MANAGE_TOPOLOGY" = true ]; then
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
      # Uses profiles from an existing declaration when present so custom
      # mounts are available on the first boot. Otherwise it uses nixos-lxc.
      echo "==> Initializing root FS on $SELECTED_POOL..."
      INSTANCE_PROFILES=()
      if [ "$USE_EXISTING_INSTANCE" = true ]; then
        while IFS= read -r instance_profile; do
          if [ -n "$instance_profile" ]; then
            INSTANCE_PROFILES+=("$instance_profile")
          fi
        done < <(${pythonWithYaml}/bin/python3 ${instanceConfigReader} \
          "$INSTANCES_YAML" "$HOSTNAME" profiles)
      fi
      if [ "''${#INSTANCE_PROFILES[@]}" -eq 0 ]; then
        INSTANCE_PROFILES=("$PROFILE")
      fi

      PROFILE_ARGS=()
      for instance_profile in "''${INSTANCE_PROFILES[@]}"; do
        PROFILE_ARGS+=(-p "$instance_profile")
      done

      if ! server_cmd incus init "$IMAGE_ALIAS" "$HOSTNAME" \
        "''${PROFILE_ARGS[@]}" -s "$SELECTED_POOL"
      then
        rollback_create "Incus initialization failed"
      fi
      CONTAINER_CREATED=true

      if [ "$USE_EXISTING_INSTANCE" = true ]; then
        ROOT_SIZE=$(${pythonWithYaml}/bin/python3 ${instanceConfigReader} \
          "$INSTANCES_YAML" "$HOSTNAME" size)
        if [ -n "$ROOT_SIZE" ]; then
          server_cmd incus config device set "$HOSTNAME" root size="$ROOT_SIZE"
        fi
      fi

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

      # `zfs receive` preserves the source snapshot. It is only transport for
      # provisioning; leaving it on every guest pins the initial store forever.
      # The reusable template snapshot above remains untouched.
      if ! server_cmd zfs destroy \
        "$NIX_PARENT_DATASET/$HOSTNAME@$NIX_TEMPLATE_SNAPSHOT_NAME"
      then
        rollback_create "Removing received nix store template snapshot failed"
      fi

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
      # Preserve a predeclared instance or append a default declaration so
      # incus-declarative-apply and incus-sync know about the new container.
      if [ "$USE_EXISTING_INSTANCE" = true ]; then
        echo "==> Preserving existing $HOSTNAME declaration in instances.yaml..."
      elif [ "$INTERMITTENT" = true ]; then
        echo "==> Adding $HOSTNAME to instances.yaml..."
        cat >> "$INSTANCES_YAML" <<YAML

$HOSTNAME:
  type: "container"
  profiles: ["nixos-lxc"]
  config:
    boot.autostart: "false"
  devices:
    root: { type: "disk", path: "/", pool: "$SELECTED_POOL", size: "4GiB" }
    nix-store: { type: "disk", path: "/nix", source: "$NIX_HOST_MOUNT_BASE/$HOSTNAME" }
    eth0: { type: "nic", nictype: "bridged", parent: "br0", hwaddr: "$MAC_ADDR" }
YAML
      else
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
      fi
      if [ "$USE_EXISTING_INSTANCE" = false ]; then
        INSTANCE_ADDED=true
      fi

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

      if [ "$VERIFY_TOPOLOGY" = true ]; then
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
      # A nonzero deploy can still mean the configuration activated but a
      # service failed during switch. Let the operator keep the provisioned
      # container in that case instead of unconditionally rolling it back.
      echo "==> Deploying NixOS config from build-nix..."
      if ! deploy_host "$HOSTNAME"; then
        $GUM style --foreground 214 --bold \
          "Host deploy returned a failure. The configuration may still have activated."

        if $GUM confirm \
          --affirmative "Keep container" \
          --negative "Roll back" \
          "Keep $HOSTNAME and the generated configuration?"
        then
          $GUM style --foreground 214 \
            "Keeping $HOSTNAME. Inspect the failed service and redeploy when ready."
        else
          rollback_create "Host deploy failed"
        fi
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

    # ══════════════════════════════════════════════════════════════
    #  TEMPLATE — rebuild the base image and the /nix template snapshot
    #
    #  Both artifacts come from one build of nixosConfigurations.lxc-template
    #  so the rootfs image and the store it boots from can never drift apart.
    #  Deploys onto a stale base fail in switch-to-configuration, so this is
    #  the fix whenever the fleet's nixpkgs moves on.
    #
    #  Flow:
    #    1. Build the rootfs tarball and Incus metadata on build-nix
    #    2. Ship both to server-nix
    #    3. Extract nix/store into a staging dataset and snapshot it @ready
    #    4. Repack the rootfs without the store, import it as the base image
    #    5. Swap the new dataset and image alias in, retiring the old ones
    #    6. Optionally boot a throwaway container off the result
    # ══════════════════════════════════════════════════════════════
    do_template() {
      require_server

      STAMP=$(date +%Y%m%d-%H%M%S)
      STAGING_DATASET="$NIX_TEMPLATE_DATASET-staging"
      RETIRED_DATASET="$NIX_TEMPLATE_DATASET-retired-$STAMP"
      REMOTE_WORK="/var/tmp/nixos-factory-template-$STAMP"

      OLD_FINGERPRINT=$(server_cmd incus image info "$IMAGE_ALIAS" 2>/dev/null \
        | grep -oE '[0-9a-f]{64}' | head -n1 || true)

      $GUM style --border rounded --padding "1 2" --border-foreground 86 \
        "Rebuild the factory base image

    Flake:    $TEMPLATE_ATTR
    Image:    $IMAGE_ALIAS
    Store:    $NIX_TEMPLATE_SNAPSHOT
    Retires:  $RETIRED_DATASET"

      if ! $GUM confirm "Rebuild the base image and nix store template?"; then
        echo "Aborted."
        return 0
      fi

      # --- Step 1: Build both artifacts from the same evaluation ---
      echo "==> Building $TEMPLATE_ATTR.tarball..."
      if ! TARBALL_OUT=$("$NIX" build --no-link --print-out-paths \
        "$NIX_CONFIG#$TEMPLATE_ATTR.tarball")
      then
        $GUM style --foreground 196 --bold "Building the rootfs tarball failed."
        return 1
      fi

      echo "==> Building $TEMPLATE_ATTR.metadata..."
      if ! METADATA_OUT=$("$NIX" build --no-link --print-out-paths \
        "$NIX_CONFIG#$TEMPLATE_ATTR.metadata")
      then
        $GUM style --foreground 196 --bold "Building the Incus metadata failed."
        return 1
      fi

      ROOTFS_TAR=$(echo "$TARBALL_OUT"/tarball/*.tar.xz)
      METADATA_TAR=$(echo "$METADATA_OUT"/tarball/*.tar.xz)

      if [ ! -f "$ROOTFS_TAR" ] || [ ! -f "$METADATA_TAR" ]; then
        $GUM style --foreground 196 --bold "Build produced no tarball to import."
        return 1
      fi

      # --- Step 2: Ship both tarballs to server-nix ---
      echo "==> Copying tarballs to $SERVER_HOST:$REMOTE_WORK..."
      server_cmd mkdir -p "$REMOTE_WORK"
      "$SCP" -q -o BatchMode=yes "$ROOTFS_TAR" "$SERVER_HOST:$REMOTE_WORK/rootfs-full.tar.xz"
      "$SCP" -q -o BatchMode=yes "$METADATA_TAR" "$SERVER_HOST:$REMOTE_WORK/metadata.tar.xz"

      template_cleanup() {
        server_cmd "umount $REMOTE_WORK/nix 2>/dev/null || true"
        server_cmd rm -rf "$REMOTE_WORK"
      }

      # --- Step 3: Stage the new nix store on its own dataset ---
      # A staging dataset means a failure here leaves the live template alone.
      echo "==> Staging nix store in $STAGING_DATASET..."
      server_cmd "zfs destroy -r $STAGING_DATASET 2>/dev/null || true"
      if ! server_cmd zfs create "$STAGING_DATASET"; then
        template_cleanup
        $GUM style --foreground 196 --bold "Could not create $STAGING_DATASET."
        return 1
      fi

      server_cmd mkdir -p "$REMOTE_WORK/nix"
      # nix-templates inherits mountpoint=legacy, so mount it by hand.
      if ! server_cmd mount -t zfs "$STAGING_DATASET" "$REMOTE_WORK/nix"; then
        server_cmd "zfs destroy -r $STAGING_DATASET"
        template_cleanup
        $GUM style --foreground 196 --bold "Could not mount $STAGING_DATASET."
        return 1
      fi

      # The dataset is mounted at /nix inside the guest, so nix/store from the
      # tarball has to land as store/ at its root.
      if ! server_cmd \
        "tar -xJf $REMOTE_WORK/rootfs-full.tar.xz -C $REMOTE_WORK/nix --strip-components=1 nix"
      then
        server_cmd "umount $REMOTE_WORK/nix; zfs destroy -r $STAGING_DATASET"
        template_cleanup
        $GUM style --foreground 196 --bold "Extracting the nix store failed."
        return 1
      fi

      if ! server_cmd zfs snapshot "$STAGING_DATASET@$NIX_TEMPLATE_SNAPSHOT_NAME"; then
        server_cmd "umount $REMOTE_WORK/nix; zfs destroy -r $STAGING_DATASET"
        template_cleanup
        $GUM style --foreground 196 --bold "Snapshotting the staged store failed."
        return 1
      fi

      if ! server_cmd umount "$REMOTE_WORK/nix"; then
        server_cmd "zfs destroy -r $STAGING_DATASET"
        template_cleanup
        $GUM style --foreground 196 --bold "Could not unmount $STAGING_DATASET."
        return 1
      fi

      # --- Step 4: Repack the rootfs without the store and import it ---
      # The store arrives through the ZFS clone, so shipping it in the image
      # too would just burn the container's 4GiB root quota.
      echo "==> Repacking rootfs without /nix/store..."
      if ! server_cmd \
        "mkdir -p $REMOTE_WORK/rootfs && tar -xJf $REMOTE_WORK/rootfs-full.tar.xz -C $REMOTE_WORK/rootfs --exclude=nix/store --exclude='nix/store/*' && mkdir -p $REMOTE_WORK/rootfs/nix/store && tar -cJf $REMOTE_WORK/rootfs.tar.xz -C $REMOTE_WORK/rootfs ."
      then
        server_cmd "zfs destroy -r $STAGING_DATASET"
        template_cleanup
        $GUM style --foreground 196 --bold "Repacking the rootfs failed."
        return 1
      fi

      echo "==> Importing the image into Incus..."
      if ! IMPORT_OUT=$(server_cmd \
        "incus image import $REMOTE_WORK/metadata.tar.xz $REMOTE_WORK/rootfs.tar.xz")
      then
        server_cmd "zfs destroy -r $STAGING_DATASET"
        template_cleanup
        $GUM style --foreground 196 --bold "Image import failed."
        return 1
      fi

      NEW_FINGERPRINT=$(echo "$IMPORT_OUT" \
        | grep -oE '[0-9a-f]{64}' | head -n1)
      if [ -z "$NEW_FINGERPRINT" ]; then
        server_cmd "zfs destroy -r $STAGING_DATASET"
        template_cleanup
        $GUM style --foreground 196 --bold "Could not read the new image fingerprint."
        return 1
      fi

      # --- Step 5: Swap the alias and dataset into place ---
      echo "==> Pointing $IMAGE_ALIAS at $NEW_FINGERPRINT..."
      server_cmd "incus image alias delete $IMAGE_ALIAS 2>/dev/null || true"
      if ! server_cmd incus image alias create "$IMAGE_ALIAS" "$NEW_FINGERPRINT"; then
        if [ -n "$OLD_FINGERPRINT" ]; then
          server_cmd incus image alias create "$IMAGE_ALIAS" "$OLD_FINGERPRINT" || true
        fi
        server_cmd "zfs destroy -r $STAGING_DATASET"
        template_cleanup
        $GUM style --foreground 196 --bold "Could not point $IMAGE_ALIAS at the new image."
        return 1
      fi

      echo "==> Retiring $NIX_TEMPLATE_DATASET to $RETIRED_DATASET..."
      if server_cmd zfs list "$NIX_TEMPLATE_DATASET" >/dev/null 2>&1; then
        if ! server_cmd zfs rename "$NIX_TEMPLATE_DATASET" "$RETIRED_DATASET"; then
          server_cmd "incus image alias delete $IMAGE_ALIAS 2>/dev/null || true"
          if [ -n "$OLD_FINGERPRINT" ]; then
            server_cmd incus image alias create "$IMAGE_ALIAS" "$OLD_FINGERPRINT" || true
          fi
          server_cmd "zfs destroy -r $STAGING_DATASET"
          template_cleanup
          $GUM style --foreground 196 --bold \
            "Could not retire $NIX_TEMPLATE_DATASET. Nothing was swapped."
          return 1
        fi
      fi

      if ! server_cmd zfs rename "$STAGING_DATASET" "$NIX_TEMPLATE_DATASET"; then
        server_cmd zfs rename "$RETIRED_DATASET" "$NIX_TEMPLATE_DATASET" || true
        server_cmd "incus image alias delete $IMAGE_ALIAS 2>/dev/null || true"
        if [ -n "$OLD_FINGERPRINT" ]; then
          server_cmd incus image alias create "$IMAGE_ALIAS" "$OLD_FINGERPRINT" || true
        fi
        template_cleanup
        $GUM style --foreground 196 --bold "Could not promote the staging dataset."
        return 1
      fi

      template_cleanup

      # --- Step 6: Optional smoke test ---
      if $GUM confirm "Boot a throwaway container off the new template?"; then
        if verify_template; then
          $GUM style --foreground 82 "Smoke test passed."
        else
          $GUM style --foreground 214 --bold \
            "Smoke test failed. To roll back:
    incus image alias delete $IMAGE_ALIAS
    incus image alias create $IMAGE_ALIAS ''${OLD_FINGERPRINT:-<previous fingerprint>}
    zfs rename $NIX_TEMPLATE_DATASET $NIX_TEMPLATE_DATASET-failed-$STAMP
    zfs rename $RETIRED_DATASET $NIX_TEMPLATE_DATASET"
        fi
      fi

      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Base image rebuilt

    Image:    $IMAGE_ALIAS -> $NEW_FINGERPRINT
    Store:    $NIX_TEMPLATE_SNAPSHOT
    Retired:  $RETIRED_DATASET
    Previous: ''${OLD_FINGERPRINT:-none}

    Destroy the retired dataset and image once a create has succeeded."
    }

    # Provision a throwaway container exactly the way do_create does, confirm
    # it boots and answers, then tear it down. Always cleans up after itself.
    verify_template() {
      CHECK_HOST="factory-template-check"
      CHECK_RESULT=1

      server_cmd "incus delete --force $CHECK_HOST 2>/dev/null || true"
      server_cmd "zfs destroy -r $NIX_PARENT_DATASET/$CHECK_HOST 2>/dev/null || true"

      echo "==> Creating $CHECK_HOST..."
      if server_cmd incus init "$IMAGE_ALIAS" "$CHECK_HOST" -p "$PROFILE" -s rpool \
        && server_cmd \
          "zfs send $NIX_TEMPLATE_SNAPSHOT | zfs receive $NIX_PARENT_DATASET/$CHECK_HOST" \
        && server_cmd zfs destroy \
          "$NIX_PARENT_DATASET/$CHECK_HOST@$NIX_TEMPLATE_SNAPSHOT_NAME" \
        && server_cmd chown -R "$UID_GID" "$NIX_HOST_MOUNT_BASE/$CHECK_HOST" \
        && server_cmd incus config device add "$CHECK_HOST" nix-store disk \
          source="$NIX_HOST_MOUNT_BASE/$CHECK_HOST" path=/nix \
        && server_cmd incus start "$CHECK_HOST"
      then
        echo "==> Waiting for $CHECK_HOST to come up..."
        for i in $(seq 1 60); do
          if server_cmd incus exec "$CHECK_HOST" -- \
            ping -c1 -W1 build-nix.lan >/dev/null 2>&1
          then
            CHECK_RESULT=0
            break
          fi
          sleep 1
        done

        if [ "$CHECK_RESULT" -eq 0 ]; then
          echo "==> Network is up. Waiting for sshd..."
          CHECK_RESULT=1
          for i in $(seq 1 30); do
            if server_cmd incus exec "$CHECK_HOST" -- \
              systemctl is-active sshd.service >/dev/null 2>&1
            then
              CHECK_RESULT=0
              break
            fi
            sleep 1
          done

          # register-nix-paths loads the store DB and sets this profile, so a
          # missing symlink means the image and the cloned store disagree.
          if [ "$CHECK_RESULT" -eq 0 ]; then
            echo "==> Checking the system profile..."
            server_cmd incus exec "$CHECK_HOST" -- \
              test -L /nix/var/nix/profiles/system || CHECK_RESULT=1
          fi
        fi

        if [ "$CHECK_RESULT" -ne 0 ]; then
          echo "==> Last 30 journal lines from $CHECK_HOST:"
          server_cmd incus exec "$CHECK_HOST" -- \
            journalctl -n 30 --no-pager 2>/dev/null || true
        fi
      fi

      echo "==> Removing $CHECK_HOST..."
      server_cmd "incus delete --force $CHECK_HOST 2>/dev/null || true"
      server_cmd "zfs destroy -r $NIX_PARENT_DATASET/$CHECK_HOST 2>/dev/null || true"

      return "$CHECK_RESULT"
    }

    # ── Dispatch to selected action ───────────────────────────────
    case "$ACTION" in
      create) do_create ;;
      rename) do_rename ;;
      delete) do_delete ;;
      template) do_template ;;
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

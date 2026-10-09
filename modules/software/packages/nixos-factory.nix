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
  # Same registry server-nix applies, so new containers boot with their declared profiles.
  incusRegistry = import ../../../hosts/server-nix/system/incus/registry.nix {
    inherit lib networkTopology;
  };
  factoryRegistryJson = pkgs.writeText "nixos-factory-incus-registry.json" (
    builtins.toJSON incusRegistry.instances
  );
  factoryNixStoresJson = pkgs.writeText "nixos-factory-nix-stores.json" (
    builtins.toJSON {
      locations = incusRegistry.nixStores;
      default = incusRegistry.defaultNixStore;
    }
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
            start = lines.index("  hostDefinitions = {\n") + 1
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

    def guests_bounds(lines):
        try:
            start = lines.index("  incusGuestNames = [\n") + 1
        except ValueError:
            raise SystemExit("missing topology incusGuestNames list")

        for end in range(start, len(lines)):
            if lines[end] == "  ];\n":
                return start, end
        raise SystemExit("unterminated topology incusGuestNames list")

    # Prints "added" or "present" so callers know whether to roll back.
    def add_guest(path, host):
        lines = read_lines(path)
        start, end = guests_bounds(lines)
        entry = f'    "{host}"\n'

        if entry in lines[start:end]:
            print("present")
            return

        at = next((i for i in range(start, end) if lines[i] > entry), end)
        lines.insert(at, entry)
        write_lines(path, lines)
        print("added")

    def remove_guest(path, host):
        lines = read_lines(path)
        start, end = guests_bounds(lines)
        entry = f'    "{host}"\n'

        if entry in lines[start:end]:
            del lines[lines.index(entry, start, end)]
            write_lines(path, lines)
            print("removed")
        else:
            print("absent")

    action = sys.argv[1]
    if action == "add":
        add(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif action == "remove":
        remove(sys.argv[2], sys.argv[3])
    elif action == "add-guest":
        add_guest(sys.argv[2], sys.argv[3])
    elif action == "remove-guest":
        remove_guest(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(f"unknown action: {action}")
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
    SSH_EXTRA_OPTS=()

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

    # Store tiers from incus/registry.nix nixStores: each container's /nix is
    # dataset <tier dataset>/<host>, bind-mounted from <tier mount>/<host>.
    NIX_STORES_JSON="${factoryNixStoresJson}"
    DEFAULT_NIX_STORE=$($JQ -r '.default' "$NIX_STORES_JSON")

    # UID/GID the nix store is chowned to — matches the container's id mapping
    # (security.idmap.base = 100000 in the nixos-lxc profile).
    UID_GID="100000:100000"

    # The repo is bind-mounted from server-nix into build-nix, so local edits
    # here are immediately visible to both hosts.
    NIX_CONFIG="/mnt/zpool/code/nix-config"
    REGISTRY_JSON="${factoryRegistryJson}"
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
        "''${SSH_EXTRA_OPTS[@]}" \
        "$SERVER_HOST" \
        "$@"
    }

    nix_store_names() {
      $JQ -r '.locations | keys[]' "$NIX_STORES_JSON"
    }

    nix_store_dataset() {
      $JQ -r --arg s "$1" '.locations[$s].dataset // empty' "$NIX_STORES_JSON"
    }

    nix_store_mount() {
      $JQ -r --arg s "$1" '.locations[$s].mount // empty' "$NIX_STORES_JSON"
    }

    # Tier name for a store source path (<tier mount>/<host>), empty if none matches.
    nix_store_for_source() {
      $JQ -r --arg m "''${1%/*}" \
        '.locations | to_entries[] | select(.value.mount == $m) | .key' "$NIX_STORES_JSON"
    }

    # Tier the registry declares for a host, empty if the host is undeclared.
    declared_nix_store() {
      declared_source=$($JQ -r --arg host "$1" \
        '.[$host].devices["nix-store"].source // empty' "$REGISTRY_JSON")
      if [ -n "$declared_source" ]; then
        nix_store_for_source "$declared_source"
      fi
    }

    # ZFS dataset actually mounted at an existing store path on server-nix.
    # Fails if the path is not its own dataset (zfs list would name the parent).
    dataset_for_source() {
      store_dataset=$(server_cmd zfs list -H -o name "$1" 2>/dev/null) || return 1
      if [ "''${store_dataset##*/}" != "''${1##*/}" ]; then
        return 1
      fi
      printf '%s\n' "$store_dataset"
    }

    require_nix_store_parent() {
      if ! server_cmd zfs list -H -o name "$1" >/dev/null 2>&1; then
        $GUM style --foreground 196 --bold "Store parent dataset $1 does not exist."
        $GUM style --foreground 214 "Deploy server-nix first; it creates the store parents."
        exit 1
      fi
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

    # Kea reservations derive from topology, so a new host's lease needs this.
    deploy_dhcp() {
      deploy networking-dhcp-nix
    }

    # ── Splash screen and action picker (skipped when scripted) ─
    ACTION="''${1:-}"
    if [ -z "$ACTION" ]; then
      clear
      $GUM style --foreground 86 --border-foreground 86 --border double \
        --align center --width 50 "$($FIGLET -f small "NIXOS FACTORY")"
      ACTION=$($GUM choose "create" "rename" "delete" "move" "template")
    fi

    # ══════════════════════════════════════════════════════════════
    #  CREATE — provision a new NixOS container end-to-end
    #
    #  Flow:
    #    1. Prompt for hostname and optional topology/DNS management
    #    2. Verify a NixOS / colmena config already exists for it
    #    3. Collect IP, storage pool, and MAC address
    #    4. Show plan and confirm
    #    5. Optionally add topology and deploy AdGuard + DHCP
    #    6. Create the container and nix store on server-nix over SSH
    #    7. List it in topology incusGuestNames so server-nix declares it
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
      IP_ADDRESS=""
      MAC_ADDR=""

      if $JQ -e --arg host "$HOSTNAME" 'has($host)' "$TOPOLOGY_JSON" >/dev/null; then
        IP_ADDRESS=$($JQ -r --arg host "$HOSTNAME" '.[$host].ip // empty' "$TOPOLOGY_JSON")
        MAC_ADDR=$($JQ -r --arg host "$HOSTNAME" '.[$host].mac // empty' "$TOPOLOGY_JSON")
        if [ -z "$IP_ADDRESS" ] || [ -z "$MAC_ADDR" ]; then
          $GUM style --foreground 196 --bold \
            "$HOSTNAME exists in topology but does not have both a LAN IP and MAC"
          exit 1
        fi
        USE_EXISTING_TOPOLOGY=true
        VERIFY_TOPOLOGY=true
        $GUM style --foreground 212 \
          "Using existing topology: $HOSTNAME.lan → $IP_ADDRESS ($MAC_ADDR)"
      elif $GUM confirm "Add $HOSTNAME to topology and deploy AdGuard DNS + DHCP?"; then
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

      # The registry was baked in when build-nix last deployed; it covers every
      # host that was already in incusGuestNames then.
      USE_EXISTING_INSTANCE=false
      if $JQ -e --arg host "$HOSTNAME" 'has($host)' "$REGISTRY_JSON" >/dev/null; then
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
        SELECTED_POOL=$($JQ -r --arg host "$HOSTNAME" \
          '.[$host].devices.root.pool // empty' "$REGISTRY_JSON")
      fi
      if [ -z "''${SELECTED_POOL:-}" ]; then
        $GUM style --foreground 212 "Select target root storage pool:"
        SELECTED_POOL=$($GUM choose "''${ROOT_POOLS[@]}")
      fi

      # The registry declares the store tier; undeclared hosts get the default.
      NIX_STORE=""
      if [ "$USE_EXISTING_INSTANCE" = true ]; then
        NIX_STORE=$(declared_nix_store "$HOSTNAME")
      fi
      if [ -z "$NIX_STORE" ]; then
        $GUM style --foreground 212 "Select nix store location:"
        mapfile -t NIX_STORE_CHOICES < <(nix_store_names)
        NIX_STORE=$($GUM choose --selected="$DEFAULT_NIX_STORE" "''${NIX_STORE_CHOICES[@]}")
        if [ "$NIX_STORE" != "$DEFAULT_NIX_STORE" ]; then
          $GUM style --foreground 214 \
            "Also set nixStore = \"$NIX_STORE\" for $HOSTNAME in hosts/server-nix/system/incus/registry.nix."
        fi
      fi
      NIX_STORE_PARENT=$(nix_store_dataset "$NIX_STORE")
      NIX_DATASET="$NIX_STORE_PARENT/$HOSTNAME"
      NIX_SOURCE="$(nix_store_mount "$NIX_STORE")/$HOSTNAME"
      require_nix_store_parent "$NIX_STORE_PARENT"
      if server_cmd zfs list -H -o name "$NIX_DATASET" >/dev/null 2>&1; then
        $GUM style --foreground 196 "Nix store dataset $NIX_DATASET already exists."
        exit 1
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
      echo "  Store:     $NIX_SOURCE ($NIX_DATASET)"
      if [ "$USE_EXISTING_INSTANCE" = true ]; then
        echo "  Registry:  existing declaration"
      else
        echo "  Registry:  defaults (adds $HOSTNAME to incusGuestNames)"
      fi
      if [ "$VERIFY_TOPOLOGY" = true ]; then
        if [ "$USE_EXISTING_TOPOLOGY" = true ]; then
          echo "  Topology:  existing ($HOSTNAME.lan → $IP_ADDRESS)"
        else
          echo "  Topology:  $HOSTNAME.lan → $IP_ADDRESS"
        fi
        echo "  DNS:       deploy adguard-nix"
        if [ "$HOSTNAME" != "networking-dhcp-nix" ]; then
          echo "  DHCP:      deploy networking-dhcp-nix"
        fi
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
      DHCP_DEPLOY_ATTEMPTED=false
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
          && server_cmd zfs list "$NIX_DATASET" >/dev/null 2>&1
        then
          echo "==> Destroying ZFS dataset $NIX_DATASET..."
          server_cmd zfs destroy -r "$NIX_DATASET" || true
        fi

        if [ "$INSTANCE_ADDED" = true ]; then
          echo "==> Removing $HOSTNAME from topology incusGuestNames..."
          ${pythonWithYaml}/bin/python3 ${topologyManager} \
            remove-guest "$TOPOLOGY_NIX" "$HOSTNAME" >/dev/null || true
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
        if [ "$DHCP_DEPLOY_ATTEMPTED" = true ]; then
          echo "==> Restoring DHCP reservations..."
          deploy_dhcp || true
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
      fi

      # An existing entry may predate the last AdGuard/Kea deploy, so apply both either way.
      if [ "$VERIFY_TOPOLOGY" = true ]; then
        echo "==> Deploying AdGuard DNS..."
        ADGUARD_DEPLOY_ATTEMPTED=true
        if ! deploy_adguard; then
          rollback_create "AdGuard deploy failed"
        fi

        # The DHCP server can't hand its own container a reservation.
        if [ "$HOSTNAME" != "networking-dhcp-nix" ]; then
          echo "==> Deploying DHCP reservations..."
          DHCP_DEPLOY_ATTEMPTED=true
          if ! deploy_dhcp; then
            rollback_create "DHCP deploy failed"
          fi
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
        done < <($JQ -r --arg host "$HOSTNAME" '.[$host].profiles[]' "$REGISTRY_JSON")
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
        ROOT_SIZE=$($JQ -r --arg host "$HOSTNAME" \
          '.[$host].devices.root.size // empty' "$REGISTRY_JSON")
        if [ -n "$ROOT_SIZE" ]; then
          server_cmd incus config device set "$HOSTNAME" root size="$ROOT_SIZE"
        fi
      fi

      # --- Step 3: Clone the template nix store ---
      # ZFS send/receive copies the pre-built /nix from the template snapshot
      # into a new dataset for this container. Both ends stay on server-nix.
      echo "==> Replicating nix store to $NIX_DATASET..."
      if ! server_cmd \
        "zfs send $NIX_TEMPLATE_SNAPSHOT | zfs receive $NIX_DATASET"
      then
        rollback_create "Nix store replication failed"
      fi
      DATASET_CREATED=true

      # `zfs receive` preserves the source snapshot. It is only transport for
      # provisioning; leaving it on every guest pins the initial store forever.
      # The reusable template snapshot above remains untouched.
      if ! server_cmd zfs destroy "$NIX_DATASET@$NIX_TEMPLATE_SNAPSHOT_NAME"
      then
        rollback_create "Removing received nix store template snapshot failed"
      fi

      # --- Step 4: Wire up devices ---
      # - chown the nix store to the container's mapped UID/GID
      # - Attach the host-side nix store as a disk device at /nix
      # - Set or create the eth0 NIC with the chosen MAC address
      echo "==> Configuring container devices on server-nix..."
      server_cmd chown -R "$UID_GID" "$NIX_SOURCE"
      server_cmd incus config device add "$HOSTNAME" nix-store disk \
        source="$NIX_SOURCE" path=/nix

      if server_cmd incus config device show "$HOSTNAME" | grep -q '^eth0:'; then
        server_cmd incus config device set "$HOSTNAME" eth0 hwaddr="$MAC_ADDR"
      else
        server_cmd incus config device add "$HOSTNAME" eth0 nic \
          nictype=bridged parent=br0 hwaddr="$MAC_ADDR"
      fi

      # --- Step 5: Add to declarative config ---
      # The registry gives every incusGuestNames entry a default instance
      # (MAC and intermittent autostart from topology); overrides go in
      # hosts/server-nix/system/incus/registry.nix.
      echo "==> Listing $HOSTNAME in topology incusGuestNames..."
      if ! GUEST_RESULT=$(${pythonWithYaml}/bin/python3 ${topologyManager} \
        add-guest "$TOPOLOGY_NIX" "$HOSTNAME")
      then
        rollback_create "Topology guest update failed"
      fi
      if [ "$GUEST_RESULT" = added ]; then
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
            "Expected $IP_ADDRESS for MAC $MAC_ADDR. Check the DHCP reservation."
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
    Store: $NIX_SOURCE"
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
    #  NOTE: This does NOT update topology, the Incus registry, colmena.nix,
    #  or the NixOS host config. Rename the host in those by hand.
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
        if ! OLD_NIX_DATASET=$(dataset_for_source "$OLD_NIX_SOURCE"); then
          $GUM style --foreground 196 "$OLD_NIX_SOURCE is not its own ZFS dataset."
          exit 1
        fi
        # Renaming keeps the dataset under the same parent, so its mount follows.
        NEW_NIX_DATASET="''${OLD_NIX_DATASET%/*}/$NEW_NAME"
        NEW_NIX_SOURCE="''${OLD_NIX_SOURCE%/*}/$NEW_NAME"
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
        echo "  Nix store: $OLD_NIX_SOURCE → $NEW_NIX_SOURCE"
        echo "  ZFS:       $OLD_NIX_DATASET → $NEW_NIX_DATASET"
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
        server_cmd zfs rename "$OLD_NIX_DATASET" "$NEW_NIX_DATASET"

        echo "==> Updating nix-store device source..."
        server_cmd incus config device set \
          "$NEW_NAME" nix-store source="$NEW_NIX_SOURCE"
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
    #    7. Remove it from topology incusGuestNames
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
        if ! NIX_DATASET=$(dataset_for_source "$NIX_SOURCE"); then
          $GUM style --foreground 214 "$NIX_SOURCE is not its own ZFS dataset; leaving it alone."
          HAS_NIX_STORE=false
        fi
      fi

      # Standard-tier root disks are copied hourly here (zfs-backups.nix).
      ROOT_BACKUP="zpool/backups/containers/$TARGET"
      HAS_ROOT_BACKUP=false
      if server_cmd zfs list -H -o name "$ROOT_BACKUP" >/dev/null 2>&1; then
        HAS_ROOT_BACKUP=true
      fi

      # --- Show plan ---
      echo ""
      $GUM style --foreground 196 --bold "DELETE plan:"
      echo "  Container: $TARGET"
      echo "  Status:    $STATE"
      if [ "$HAS_NIX_STORE" = true ]; then
        echo "  Nix store: $NIX_SOURCE (ZFS: $NIX_DATASET)"
      fi
      if [ "$HAS_ROOT_BACKUP" = true ]; then
        echo "  Backup:    $ROOT_BACKUP (kept unless you choose otherwise)"
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

      # The zpool copy is the last trace of the container's state once it's gone.
      DESTROY_ROOT_BACKUP=false
      if [ "$HAS_ROOT_BACKUP" = true ]; then
        if $GUM confirm --default=No "Also destroy its zpool backup ($ROOT_BACKUP)?"; then
          DESTROY_ROOT_BACKUP=true
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
      if [ "$DESTROY_ROOT_BACKUP" = true ]; then
        echo "==> Destroying ZFS dataset $ROOT_BACKUP..."
        server_cmd zfs destroy -r "$ROOT_BACKUP"
      fi

      # Drop it from incusGuestNames so server-nix stops declaring it
      if [ "$(${pythonWithYaml}/bin/python3 ${topologyManager} \
        remove-guest "$TOPOLOGY_NIX" "$TARGET")" = removed ]
      then
        echo "==> Removed $TARGET from topology incusGuestNames"
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
    #  MOVE — put a container's root disk and /nix on its declared tier
    #
    #  Flow:
    #    1. Work out what differs from the registry: root pool, store, or both
    #    2. Copy the store to its new tier while the container keeps running
    #    3. Stop it, copy what changed, repoint nix-store
    #    4. Move the root disk with `incus move --storage` (Incus copies it and
    #       only deletes the original once the copy succeeded)
    #    5. Start it and wait for boot; on failure put everything back
    #    6. Keep or destroy the old store
    #
    #  Scriptable: `nixos-factory move <host> [flags]` exits 0 when moved or
    #  already in place, 3 when declined, 1 on failure (rolled back).
    #    --no-confirm                       skip the plan confirmation
    #    --strict                           a degraded boot fails (and rolls back)
    #    --destroy-old-store/--keep-old-store  skip that question
    #  `nixos-factory move-plan` prints a TSV line per container that differs.
    #  server-nix is reached by IP, so moving DNS can't strand the factory.
    # ══════════════════════════════════════════════════════════════
    use_server_ip() {
      SERVER_IP=$($JQ -r '.["server-nix"].ip // empty' "$TOPOLOGY_JSON")
      if [ -n "$SERVER_IP" ]; then
        SERVER_HOST="root@$SERVER_IP"
        SSH_EXTRA_OPTS=(-o HostKeyAlias=server-nix.lan)
      fi
    }

    load_instances() {
      if ! INSTANCES_JSON=$(server_cmd incus list --format json); then
        $GUM style --foreground 196 --bold "Could not list Incus instances."
        exit 1
      fi
    }

    instance_field() {
      printf '%s' "$INSTANCES_JSON" | $JQ -r --arg h "$1" ".[] | select(.name == \$h) | $2"
    }

    # Display name for a store source: its tier, or downloadHDD for the old layout.
    store_label() {
      label=$(nix_store_for_source "$1")
      if [ -n "$label" ]; then
        echo "$label"
      elif [ "''${1%/*}" = "/mnt/nix-stores" ]; then
        echo "downloadHDD"
      else
        echo "''${1%/*}"
      fi
    }

    # Sets ROOT_FROM/ROOT_TO, STORE_FROM/STORE_TO and MOVE_ROOT/MOVE_STORE for $1.
    plan_move() {
      ROOT_FROM=$(instance_field "$1" '.expanded_devices.root.pool // empty')
      ROOT_TO=$($JQ -r --arg h "$1" '.[$h].devices.root.pool // empty' "$REGISTRY_JSON")
      STORE_FROM=$(instance_field "$1" '.devices["nix-store"].source // empty')
      STORE_TO=""
      declared_store=$(declared_nix_store "$1")
      if [ -n "$declared_store" ]; then
        STORE_TO="$(nix_store_mount "$declared_store")/$1"
      fi
      MOVE_ROOT=false
      if [ -n "$ROOT_FROM" ] && [ -n "$ROOT_TO" ] && [ "$ROOT_FROM" != "$ROOT_TO" ]; then
        MOVE_ROOT=true
      fi
      MOVE_STORE=false
      if [ -n "$STORE_FROM" ] && [ -n "$STORE_TO" ] && [ "$STORE_FROM" != "$STORE_TO" ]; then
        MOVE_STORE=true
      fi
    }

    # host, state, root from, root to, root bytes, store from, store to, store bytes
    # ("-" where that part stays put). Only containers that differ are listed.
    do_move_plan() {
      use_server_ip
      require_server
      load_instances
      ZFS_LIST=$(server_cmd zfs list -H -p -o name,used,mountpoint -t filesystem)
      POOL_SOURCES=$(server_cmd incus storage list --format json \
        | $JQ -r '.[] | [.name, (.config.source // "")] | @tsv')

      while IFS= read -r host; do
        plan_move "$host"
        if [ "$MOVE_ROOT" = false ] && [ "$MOVE_STORE" = false ]; then
          continue
        fi
        root_from="-" root_to="-" root_used="-"
        if [ "$MOVE_ROOT" = true ]; then
          root_from="$ROOT_FROM" root_to="$ROOT_TO"
          pool_source=$(awk -F'\t' -v p="$ROOT_FROM" '$1 == p { print $2 }' <<< "$POOL_SOURCES")
          root_used=$(awk -v d="$pool_source/containers/$host" '$1 == d { print $2 }' <<< "$ZFS_LIST")
        fi
        store_from="-" store_to="-" store_used="-"
        if [ "$MOVE_STORE" = true ]; then
          store_from=$(store_label "$STORE_FROM")
          store_to=$(store_label "$STORE_TO")
          store_used=$(awk -v m="$STORE_FROM" '$3 == m { print $2 }' <<< "$ZFS_LIST")
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$host" \
          "$(instance_field "$host" '.status')" \
          "$root_from" "$root_to" "''${root_used:--}" \
          "$store_from" "$store_to" "''${store_used:--}"
      done < <(printf '%s' "$INSTANCES_JSON" | $JQ -r '.[].name' | sort)
    }

    do_move() {
      MOVE_HOST="''${1:-}"
      if [ "$#" -gt 0 ]; then
        shift
      fi
      NO_CONFIRM=false
      STRICT=false
      OLD_STORE_ACTION=ask
      for flag in "$@"; do
        case "$flag" in
          --no-confirm) NO_CONFIRM=true ;;
          --strict) STRICT=true ;;
          --destroy-old-store) OLD_STORE_ACTION=destroy ;;
          --keep-old-store) OLD_STORE_ACTION=keep ;;
          *)
            echo "nixos-factory move: unknown flag $flag" >&2
            exit 2
            ;;
        esac
      done

      use_server_ip
      require_server
      load_instances

      if [ -n "$MOVE_HOST" ]; then
        if ! printf '%s' "$INSTANCES_JSON" \
          | $JQ -e --arg h "$MOVE_HOST" 'any(.[]; .name == $h)' >/dev/null
        then
          $GUM style --foreground 196 --bold "No container named $MOVE_HOST."
          exit 1
        fi
        HOST="$MOVE_HOST"
      else
        PENDING=()
        while IFS= read -r host; do
          plan_move "$host"
          if [ "$MOVE_ROOT" = true ] || [ "$MOVE_STORE" = true ]; then
            PENDING+=("$host")
          fi
        done < <(printf '%s' "$INSTANCES_JSON" | $JQ -r '.[].name' | sort)

        if [ "''${#PENDING[@]}" -eq 0 ]; then
          $GUM style --foreground 82 "Every container already matches the registry."
          return 1
        fi
        $GUM style --foreground 212 "Select container to move (''${#PENDING[@]} differ from the registry):"
        HOST=$($GUM choose "''${PENDING[@]}")
      fi

      plan_move "$HOST"
      if [ "$MOVE_ROOT" = false ] && [ "$MOVE_STORE" = false ]; then
        $GUM style --foreground 82 "$HOST already matches the registry; nothing to move."
        exit 0
      fi

      STATE=$(instance_field "$HOST" '.status')
      WAS_RUNNING=false
      if [ "$STATE" = "Running" ]; then
        WAS_RUNNING=true
      fi

      if [ "$MOVE_STORE" = true ]; then
        OLD_SOURCE="$STORE_FROM"
        NEW_SOURCE="$STORE_TO"
        NEW_STORE=$(declared_nix_store "$HOST")
        NEW_PARENT=$(nix_store_dataset "$NEW_STORE")
        NEW_DATASET="$NEW_PARENT/$HOST"
        if ! OLD_DATASET=$(dataset_for_source "$OLD_SOURCE"); then
          $GUM style --foreground 196 "$OLD_SOURCE is not its own ZFS dataset."
          exit 1
        fi
        require_nix_store_parent "$NEW_PARENT"
        if server_cmd zfs list -H -o name "$NEW_DATASET" >/dev/null 2>&1; then
          $GUM style --foreground 196 "$NEW_DATASET already exists (a failed earlier move?)."
          $GUM style --foreground 214 "Destroy it on server-nix if it is stale, then retry."
          exit 1
        fi
        OLD_USED=$(server_cmd zfs get -H -o value used "$OLD_DATASET")
      fi

      if [ "$MOVE_ROOT" = true ]; then
        if ! server_cmd incus storage show "$ROOT_TO" >/dev/null 2>&1; then
          $GUM style --foreground 196 "Storage pool $ROOT_TO does not exist; deploy server-nix first."
          exit 1
        fi
        ROOT_POOL_SOURCE=$(server_cmd incus storage get "$ROOT_FROM" source)
        OLD_ROOT_DATASET="$ROOT_POOL_SOURCE/containers/$HOST"
        ROOT_USED=$(server_cmd zfs get -H -o value used "$OLD_ROOT_DATASET" 2>/dev/null || echo "?")
      fi

      echo ""
      $GUM style --foreground 86 --bold "Move plan:"
      echo "  Container: $HOST ($STATE)"
      if [ "$MOVE_ROOT" = true ]; then
        echo "  Root disk: $ROOT_FROM → $ROOT_TO ($ROOT_USED; its old snapshots are dropped)"
      else
        echo "  Root disk: stays on $ROOT_FROM"
      fi
      if [ "$MOVE_STORE" = true ]; then
        echo "  Nix store: $(store_label "$OLD_SOURCE") → $(store_label "$NEW_SOURCE") ($OLD_DATASET, $OLD_USED)"
      else
        echo "  Nix store: stays on $(store_label "$STORE_FROM")"
      fi
      if [ "$WAS_RUNNING" = true ]; then
        echo "  Downtime:  stop, final store copy, root disk copy, start"
      fi
      echo ""
      if [ "$NO_CONFIRM" = false ] && ! $GUM confirm "Move $HOST?"; then
        $GUM style --foreground 214 "Aborted."
        if [ -n "$MOVE_HOST" ]; then
          exit 3
        fi
        return 1
      fi

      SNAP="factory-move-$(date +%Y%m%d%H%M%S)"

      drop_move_snapshots() {
        if [ "$MOVE_STORE" = true ]; then
          server_cmd "zfs destroy $OLD_DATASET@$SNAP-a; zfs destroy $OLD_DATASET@$SNAP-b" \
            >/dev/null 2>&1 || true
        fi
      }

      move_failed() {
        $GUM style --foreground 196 --bold "$1 — putting $HOST back where it was..."
        server_cmd incus stop "$HOST" --force >/dev/null 2>&1 || true
        if [ "$MOVE_ROOT" = true ]; then
          live_pool=$(server_cmd incus query "/1.0/instances/$HOST" 2>/dev/null \
            | $JQ -r '.expanded_devices.root.pool // empty' || true)
          if [ -z "$live_pool" ]; then
            $GUM style --foreground 196 --bold \
              "Incus no longer lists $HOST. Check 'incus list' and the pools on server-nix by hand."
          elif [ "$live_pool" != "$ROOT_FROM" ]; then
            echo "==> Moving the root disk back to $ROOT_FROM..."
            server_cmd incus move "$HOST" --storage "$ROOT_FROM" \
              || $GUM style --foreground 196 --bold \
                "Could not move the root disk back; $HOST stays on $live_pool."
          fi
        fi
        if [ "$MOVE_STORE" = true ]; then
          server_cmd incus config device set "$HOST" nix-store source="$OLD_SOURCE" || true
          server_cmd zfs destroy -r "$NEW_DATASET" >/dev/null 2>&1 || true
          drop_move_snapshots
        fi
        if [ "$WAS_RUNNING" = true ]; then
          server_cmd incus start "$HOST" || true
        fi
        exit 1
      }

      if [ "$MOVE_STORE" = true ]; then
        echo "==> Copying $OLD_DATASET to $NEW_DATASET while $HOST runs..."
        if ! server_cmd "zfs snapshot $OLD_DATASET@$SNAP-a \
          && zfs send $OLD_DATASET@$SNAP-a | zfs receive -u $NEW_DATASET"
        then
          server_cmd zfs destroy -r "$NEW_DATASET" >/dev/null 2>&1 || true
          drop_move_snapshots
          $GUM style --foreground 196 --bold "Initial copy failed. $HOST was not touched."
          exit 1
        fi
      fi

      if [ "$WAS_RUNNING" = true ]; then
        echo "==> Stopping $HOST..."
        server_cmd incus stop "$HOST" --timeout 60 \
          || server_cmd incus stop "$HOST" --force \
          || move_failed "Stopping $HOST failed"
      fi

      if [ "$MOVE_STORE" = true ]; then
        echo "==> Copying store changes since the first pass..."
        server_cmd "zfs snapshot $OLD_DATASET@$SNAP-b \
          && zfs send -i @$SNAP-a $OLD_DATASET@$SNAP-b | zfs receive -u -F $NEW_DATASET" \
          || move_failed "Final store copy failed"
        # Received snapshots would pin the old store contents forever.
        server_cmd "zfs destroy $NEW_DATASET@$SNAP-a && zfs destroy $NEW_DATASET@$SNAP-b" \
          || move_failed "Dropping transfer snapshots failed"
        server_cmd zfs mount "$NEW_DATASET" || move_failed "Mounting $NEW_DATASET failed"

        echo "==> Pointing $HOST's nix-store at $NEW_SOURCE..."
        server_cmd incus config device set "$HOST" nix-store source="$NEW_SOURCE" \
          || move_failed "Updating the nix-store device failed"
      fi

      if [ "$MOVE_ROOT" = true ]; then
        echo "==> Moving the root disk to $ROOT_TO..."
        server_cmd incus move "$HOST" --storage "$ROOT_TO" \
          || move_failed "Moving the root disk failed"
        live_pool=$(server_cmd incus query "/1.0/instances/$HOST" \
          | $JQ -r '.expanded_devices.root.pool // empty')
        if [ "$live_pool" != "$ROOT_TO" ]; then
          move_failed "Root disk reports pool '$live_pool' after the move"
        fi
        if server_cmd zfs list -H -o name "$OLD_ROOT_DATASET" >/dev/null 2>&1; then
          $GUM style --foreground 214 \
            "Incus left $OLD_ROOT_DATASET behind; check and destroy it by hand."
        fi
      fi

      if [ "$WAS_RUNNING" = true ]; then
        echo "==> Starting $HOST..."
        server_cmd incus start "$HOST" || move_failed "Starting $HOST failed"

        echo "==> Waiting for $HOST to finish booting..."
        BOOT_STATE=""
        for i in $(seq 1 60); do
          BOOT_STATE=$(server_cmd incus exec "$HOST" -- \
            systemctl is-system-running 2>/dev/null || true)
          case "$BOOT_STATE" in
            running|degraded) break ;;
          esac
          sleep 3
        done

        case "$BOOT_STATE" in
          running) ;;
          degraded)
            $GUM style --foreground 214 "$HOST booted degraded. Failed units:"
            server_cmd incus exec "$HOST" -- systemctl --failed --no-legend || true
            if [ "$STRICT" = true ]; then
              move_failed "Degraded after the move (--strict)"
            elif ! $GUM confirm "Keep $HOST where it is now anyway?"; then
              move_failed "Degraded after the move"
            fi
            ;;
          *) move_failed "$HOST did not finish booting (state: ''${BOOT_STATE:-unknown})" ;;
        esac
      fi

      drop_move_snapshots
      FINAL_ROOT="$ROOT_FROM"
      FINAL_STORE="$STORE_FROM"
      if [ "$MOVE_ROOT" = true ]; then
        FINAL_ROOT="$ROOT_TO"
      fi
      if [ "$MOVE_STORE" = true ]; then
        FINAL_STORE="$NEW_SOURCE"
      fi
      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "$HOST moved: root disk on $FINAL_ROOT, store on $(store_label "$FINAL_STORE")"

      if [ "$MOVE_STORE" = true ]; then
        case "$OLD_STORE_ACTION" in
          destroy) DESTROY_OLD=true ;;
          keep) DESTROY_OLD=false ;;
          *)
            DESTROY_OLD=false
            if $GUM confirm --default=No "Destroy the old store $OLD_DATASET ($OLD_USED)?"; then
              DESTROY_OLD=true
            fi
            ;;
        esac
        if [ "$DESTROY_OLD" = true ]; then
          echo "==> Destroying $OLD_DATASET..."
          server_cmd zfs destroy -r "$OLD_DATASET"
        else
          $GUM style --foreground 214 \
            "Kept $OLD_DATASET. Remove it later with: zfs destroy -r $OLD_DATASET"
        fi
      fi
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
      CHECK_DATASET="$(nix_store_dataset "$DEFAULT_NIX_STORE")/$CHECK_HOST"
      CHECK_SOURCE="$(nix_store_mount "$DEFAULT_NIX_STORE")/$CHECK_HOST"

      server_cmd "incus delete --force $CHECK_HOST 2>/dev/null || true"
      server_cmd "zfs destroy -r $CHECK_DATASET 2>/dev/null || true"

      echo "==> Creating $CHECK_HOST..."
      if server_cmd incus init "$IMAGE_ALIAS" "$CHECK_HOST" -p "$PROFILE" -s rpool \
        && server_cmd \
          "zfs send $NIX_TEMPLATE_SNAPSHOT | zfs receive $CHECK_DATASET" \
        && server_cmd zfs destroy "$CHECK_DATASET@$NIX_TEMPLATE_SNAPSHOT_NAME" \
        && server_cmd chown -R "$UID_GID" "$CHECK_SOURCE" \
        && server_cmd incus config device add "$CHECK_HOST" nix-store disk \
          source="$CHECK_SOURCE" path=/nix \
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
      server_cmd "zfs destroy -r $CHECK_DATASET 2>/dev/null || true"

      return "$CHECK_RESULT"
    }

    # ── Dispatch to selected action ───────────────────────────────
    case "$ACTION" in
      create) do_create ;;
      rename) do_rename ;;
      delete) do_delete ;;
      # move-store is the old name, kept so existing scripts still work.
      move|move-store)
        if [ -n "''${2:-}" ]; then
          shift
          do_move "$@"
        else
          while do_move && $GUM confirm "Move another container?"; do
            clear
          done
        fi
        ;;
      move-plan) do_move_plan ;;
      template) do_template ;;
      *)
        echo "usage: nixos-factory [create|rename|delete|move [host] [flags]|move-plan|template]" >&2
        exit 2
        ;;
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

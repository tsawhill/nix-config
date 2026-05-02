{ config, pkgs, ... }:

let
  pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  yamlEngine = pkgs.writeText "incus-sync-engine.py" ''
    import json
    import sys

    INSTANCE_CONFIG_SKIP_PREFIXES = ["volatile.", "image."]

    DEVICE_KEY_ORDER = {
        "disk": ["type", "path", "pool", "size", "source", "shift"],
        "nic": ["type", "nictype", "parent", "hwaddr"],
    }

    def ordered_device_keys(dev):
        dev_type = dev.get("type", "")
        order = DEVICE_KEY_ORDER.get(dev_type, ["type"])
        first = [k for k in order if k in dev]
        rest = sorted(k for k in dev if k not in first)
        return first + rest

    def quote(v):
        return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'

    def format_profile(name, profile):
        lines = [f"{name}:"]
        lines.append(f"  description: {quote(profile.get('description', ''))}")

        cfg = profile.get("config") or {}
        if not cfg:
            lines.append("  config: {}")
        else:
            lines.append("  config:")
            for k in sorted(cfg):
                lines.append(f"    {k}: {quote(cfg[k])}")

        devs = profile.get("devices") or {}
        if not devs:
            lines.append("  devices: {}")
        else:
            lines.append("  devices:")
            for dname in sorted(devs):
                lines.append(f"    {dname}:")
                dev = devs[dname]
                for k in ordered_device_keys(dev):
                    lines.append(f"      {k}: {quote(dev[k])}")

        return "\n".join(lines)

    def format_instance(name, instance):
        lines = [f"{name}:"]
        lines.append(f"  type: {quote(instance['type'])}")

        profiles = instance.get("profiles") or []
        prof_str = ", ".join(quote(p) for p in profiles)
        lines.append(f"  profiles: [{prof_str}]")

        cfg = {
            k: str(v)
            for k, v in (instance.get("config") or {}).items()
            if not any(k.startswith(pfx) for pfx in INSTANCE_CONFIG_SKIP_PREFIXES)
        }
        if not cfg:
            lines.append("  config: {}")
        else:
            lines.append("  config:")
            for k in sorted(cfg):
                lines.append(f"    {k}: {quote(cfg[k])}")

        devs = instance.get("devices") or {}
        if not devs:
            lines.append("  devices: {}")
        else:
            lines.append("  devices:")
            priority = ["root", "nix-store", "eth0"]
            ordered = [d for d in priority if d in devs]
            ordered += sorted(d for d in devs if d not in priority)

            for dname in ordered:
                dev = devs[dname]
                parts = []
                for k in ordered_device_keys(dev):
                    parts.append(f"{k}: {quote(dev[k])}")
                flow = ", ".join(parts)
                lines.append(f"    {dname}: {{ {flow} }}")

        return "\n".join(lines)

    def profile_sort_key(name):
        if name == "default":
            return (0, name)
        if name == "nixos-lxc":
            return (1, name)
        return (2, name)

    def instance_sort_key(inst):
        name = inst["name"]
        is_vm = 1 if inst.get("type") == "virtual-machine" else 2
        return (is_vm, name)

    def main():
        if len(sys.argv) < 2:
            print("usage: engine.py <generate-profiles|generate-instances>", file=sys.stderr)
            sys.exit(2)

        mode = sys.argv[1]
        data = json.load(sys.stdin)

        if mode == "generate-profiles":
            data.sort(key=lambda p: profile_sort_key(p["name"]))
            blocks = [format_profile(p["name"], p) for p in data]
            print("\n\n".join(blocks) + "\n")

        elif mode == "generate-instances":
            data.sort(key=instance_sort_key)
            blocks = [format_instance(i["name"], i) for i in data]
            print("\n\n".join(blocks) + "\n")

        else:
            print(f"unknown mode: {mode}", file=sys.stderr)
            sys.exit(2)

    main()
  '';

  queryScript = pkgs.writeShellScript "incus-sync-query" ''
    set -euo pipefail
    JQ="${pkgs.jq}/bin/jq"
    PYTHON="${pythonWithYaml}/bin/python3"
    ENGINE="${yamlEngine}"
    OUTDIR="$1"

    # Query profiles
    profiles_json="[]"
    while IFS= read -r url; do
      obj=$(incus query "$url")
      profiles_json=$(printf '%s' "$profiles_json" | $JQ --argjson o "$obj" '. + [$o]')
    done < <(incus query /1.0/profiles | $JQ -r '.[]')
    printf '%s' "$profiles_json" | $PYTHON "$ENGINE" generate-profiles > "$OUTDIR/live-profiles.yaml"

    # Query instances
    instances_json="[]"
    while IFS= read -r url; do
      obj=$(incus query "$url")
      instances_json=$(printf '%s' "$instances_json" | $JQ --argjson o "$obj" '. + [$o]')
    done < <(incus query /1.0/instances | $JQ -r '.[]')
    printf '%s' "$instances_json" | $PYTHON "$ENGINE" generate-instances > "$OUTDIR/live-instances.yaml"
  '';

  incusSyncScript = pkgs.writeShellScriptBin "incus-sync" ''
    set -euo pipefail

    GUM="${pkgs.gum}/bin/gum"
    FIGLET="${pkgs.figlet}/bin/figlet"
    DIFF="${pkgs.diffutils}/bin/diff"

    PROFILES_YAML="/mnt/nix-config/hosts/server-nix/system/incus/profiles.yaml"
    INSTANCES_YAML="/mnt/nix-config/hosts/server-nix/system/incus/instances.yaml"

    WORKDIR=$(mktemp -d)
    trap 'rm -rf "$WORKDIR"' EXIT

    clear
    $GUM style --foreground 86 --border-foreground 86 --border double \
      --align center --width 50 "$($FIGLET -f small "INCUS SYNC")"

    DIRECTION=$($GUM choose "push  (YAML → Runtime)" "pull  (Runtime → YAML)")

    $GUM spin --spinner pulse --title "Querying live Incus state..." -- \
      ${queryScript} "$WORKDIR"

    has_changes=false

    show_diff() {
      local label="$1" file_a="$2" file_b="$3"
      echo ""
      $GUM style --foreground 212 --bold "$label"
      if $DIFF -u "$file_a" "$file_b" > /dev/null 2>&1; then
        $GUM style --foreground 82 "  No changes."
      else
        $DIFF --color=always -u "$file_a" "$file_b" || true
        has_changes=true
      fi
    }

    case "$DIRECTION" in
      push*)
        show_diff \
          "═══ Profile Changes (live ← YAML) ═══" \
          "$WORKDIR/live-profiles.yaml" "$PROFILES_YAML"
        show_diff \
          "═══ Instance Changes (live ← YAML) ═══" \
          "$WORKDIR/live-instances.yaml" "$INSTANCES_YAML"

        echo ""
        if [ "$has_changes" = false ]; then
          $GUM style --foreground 82 --border rounded --padding "1 2" \
            "Already in sync. Nothing to do."
          exit 0
        fi

        if ! $GUM confirm "Apply YAML config to live Incus?"; then
          $GUM style --foreground 214 "Aborted. No changes made."
          exit 0
        fi

        incus-declarative-apply
        $GUM style --foreground 82 --border rounded --padding "1 2" \
          "Push complete. Live Incus state updated from YAML."
        ;;

      pull*)
        show_diff \
          "═══ Profile Changes (YAML ← live) ═══" \
          "$PROFILES_YAML" "$WORKDIR/live-profiles.yaml"
        show_diff \
          "═══ Instance Changes (YAML ← live) ═══" \
          "$INSTANCES_YAML" "$WORKDIR/live-instances.yaml"

        echo ""
        if [ "$has_changes" = false ]; then
          $GUM style --foreground 82 --border rounded --padding "1 2" \
            "Already in sync. Nothing to do."
          exit 0
        fi

        if ! $GUM confirm "Overwrite YAML files with live state?"; then
          $GUM style --foreground 214 "Aborted. No files modified."
          exit 0
        fi

        cp "$WORKDIR/live-profiles.yaml" "$PROFILES_YAML"
        cp "$WORKDIR/live-instances.yaml" "$INSTANCES_YAML"
        $GUM style --foreground 82 --border rounded --padding "1 2" \
          "Pull complete. YAML files updated:
    $PROFILES_YAML
    $INSTANCES_YAML"
        ;;
    esac
  '';
in
{
  environment.systemPackages = [
    pkgs.gum
    pkgs.figlet
    pkgs.jq
    pythonWithYaml
    incusSyncScript
  ];
}

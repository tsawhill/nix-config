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
        "gpu": ["type", "gputype", "pci"],
    }

    # ANSI colors
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    CYAN = "\033[36m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RESET = "\033[0m"

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
        desc = profile.get("description") or ""
        lines.append(f"  description: {quote(desc)}")

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

    # --- Semantic diff ---

    def fmt_device_inline(dev):
        parts = []
        for k in ordered_device_keys(dev):
            parts.append(f"{k}={dev[k]}")
        return ", ".join(parts)

    def diff_dicts(label, old, new, indent="  "):
        lines = []
        all_keys = sorted(set(list(old) + list(new)))
        for k in all_keys:
            if k in old and k not in new:
                lines.append(f"{indent}{RED}- {k}: {old[k]}{RESET}")
            elif k not in old and k in new:
                lines.append(f"{indent}{GREEN}+ {k}: {new[k]}{RESET}")
            elif str(old[k]) != str(new[k]):
                lines.append(f"{indent}{RED}- {k}: {old[k]}{RESET}")
                lines.append(f"{indent}{GREEN}+ {k}: {new[k]}{RESET}")
        return lines

    def diff_devices(old_devs, new_devs):
        lines = []
        all_devs = sorted(set(list(old_devs) + list(new_devs)))
        for dname in all_devs:
            if dname in old_devs and dname not in new_devs:
                lines.append(f"    {RED}- {dname}: {fmt_device_inline(old_devs[dname])}{RESET}")
            elif dname not in old_devs and dname in new_devs:
                lines.append(f"    {GREEN}+ {dname}: {fmt_device_inline(new_devs[dname])}{RESET}")
            else:
                dev_changes = diff_dicts(dname, old_devs[dname], new_devs[dname], "      ")
                if dev_changes:
                    lines.append(f"    {dname}:")
                    lines.extend(dev_changes)
        return lines

    def diff_profiles(source, target, direction):
        """Compare profiles. source=current state, target=desired state."""
        lines = []
        all_names = sorted(set(list(source) + list(target)), key=profile_sort_key)
        has_changes = False

        for name in all_names:
            if name in source and name not in target:
                has_changes = True
                lines.append(f"  {RED}{BOLD}{name}{RESET}{RED} (will be removed){RESET}")
            elif name not in source and name in target:
                if direction == "push":
                    # On push, YAML-only profiles can't be pushed (they don't exist in runtime yet)
                    lines.append(f"  {YELLOW}{BOLD}{name}{RESET}{YELLOW} (declared in YAML but not in runtime — skipped){RESET}")
                else:
                    has_changes = True
                    lines.append(f"  {GREEN}{BOLD}{name}{RESET}{GREEN} (will be added){RESET}")
                    t = target[name]
                    desc = t.get("description") or ""
                    if desc:
                        lines.append(f"    description: {desc}")
                    for dk, dv in (t.get("devices") or {}).items():
                        lines.append(f"    {GREEN}+ device {dk}: {fmt_device_inline(dv)}{RESET}")
            else:
                s, t = source[name], target[name]
                changes = []

                s_desc = s.get("description") or ""
                t_desc = t.get("description") or ""
                if s_desc != t_desc:
                    changes.append(f"    description: {RED}{s_desc}{RESET} → {GREEN}{t_desc}{RESET}")

                cfg_diff = diff_dicts("config", s.get("config") or {}, t.get("config") or {}, "    ")
                changes.extend(cfg_diff)

                dev_diff = diff_devices(s.get("devices") or {}, t.get("devices") or {})
                changes.extend(dev_diff)

                if changes:
                    has_changes = True
                    lines.append(f"  {BOLD}{name}{RESET}")
                    lines.extend(changes)

        if not has_changes:
            lines.append(f"  {DIM}No changes.{RESET}")

        return has_changes, "\n".join(lines)

    def diff_instances(source, target, direction):
        """Compare instances. source=current state, target=desired state."""
        lines = []
        all_names = sorted(set(list(source) + list(target)))
        has_changes = False

        for name in all_names:
            if name in source and name not in target:
                has_changes = True
                lines.append(f"  {RED}{BOLD}{name}{RESET}{RED} (will be removed){RESET}")
            elif name not in source and name in target:
                if direction == "push":
                    # On push, YAML-only instances can't be pushed (nix-store likely doesn't exist)
                    lines.append(f"  {YELLOW}{BOLD}{name}{RESET}{YELLOW} (declared in YAML but not running — skipped){RESET}")
                else:
                    has_changes = True
                    lines.append(f"  {GREEN}{BOLD}{name}{RESET}{GREEN} (will be added){RESET}")
            else:
                s, t = source[name], target[name]
                changes = []

                if s.get("type") != t.get("type"):
                    changes.append(f"    type: {RED}{s.get('type')}{RESET} → {GREEN}{t.get('type')}{RESET}")

                s_prof = s.get("profiles") or []
                t_prof = t.get("profiles") or []
                if s_prof != t_prof:
                    changes.append(f"    profiles: {RED}{s_prof}{RESET} → {GREEN}{t_prof}{RESET}")

                s_cfg = {
                    k: str(v) for k, v in (s.get("config") or {}).items()
                    if not any(k.startswith(pfx) for pfx in INSTANCE_CONFIG_SKIP_PREFIXES)
                }
                t_cfg = {
                    k: str(v) for k, v in (t.get("config") or {}).items()
                    if not any(k.startswith(pfx) for pfx in INSTANCE_CONFIG_SKIP_PREFIXES)
                }
                cfg_diff = diff_dicts("config", s_cfg, t_cfg, "    ")
                changes.extend(cfg_diff)

                dev_diff = diff_devices(s.get("devices") or {}, t.get("devices") or {})
                changes.extend(dev_diff)

                if changes:
                    has_changes = True
                    lines.append(f"  {BOLD}{name}{RESET}")
                    lines.extend(changes)

        if not has_changes:
            lines.append(f"  {DIM}No changes.{RESET}")

        return has_changes, "\n".join(lines)

    def main():
        if len(sys.argv) < 2:
            print("usage: engine.py <mode> [args...]", file=sys.stderr)
            sys.exit(2)

        mode = sys.argv[1]

        if mode == "generate-profiles":
            data = json.load(sys.stdin)
            data.sort(key=lambda p: profile_sort_key(p["name"]))
            blocks = [format_profile(p["name"], p) for p in data]
            print("\n\n".join(blocks) + "\n")

        elif mode == "generate-instances":
            data = json.load(sys.stdin)
            data.sort(key=instance_sort_key)
            blocks = [format_instance(i["name"], i) for i in data]
            print("\n\n".join(blocks) + "\n")

        elif mode == "semantic-diff":
            if len(sys.argv) < 5:
                print("usage: engine.py semantic-diff <direction> <live.json> <yaml.json>", file=sys.stderr)
                sys.exit(2)
            direction = sys.argv[2]
            with open(sys.argv[3]) as f:
                live = json.load(f)
            with open(sys.argv[4]) as f:
                yaml_data = json.load(f)

            live_profiles = {p["name"]: p for p in live.get("profiles", [])}
            yaml_profiles = yaml_data.get("profiles", {})
            live_instances = {i["name"]: i for i in live.get("instances", [])}
            yaml_instances = yaml_data.get("instances", {})

            if direction == "push":
                source_p, target_p = live_profiles, yaml_profiles
                source_i, target_i = live_instances, yaml_instances
                label = "live → YAML"
            else:
                source_p, target_p = yaml_profiles, live_profiles
                source_i, target_i = yaml_instances, live_instances
                label = "YAML → live"

            print(f"{BOLD}{CYAN}═══ Profile Changes ({label}) ═══{RESET}")
            p_changed, p_output = diff_profiles(source_p, target_p, direction)
            print(p_output)
            print()
            print(f"{BOLD}{CYAN}═══ Instance Changes ({label}) ═══{RESET}")
            i_changed, i_output = diff_instances(source_i, target_i, direction)
            print(i_output)

            sys.exit(0 if (p_changed or i_changed) else 1)

        else:
            print(f"unknown mode: {mode}", file=sys.stderr)
            sys.exit(2)

    main()
  '';

  yamlToJson = pkgs.writeShellScriptBin "incus-yaml-to-json" ''
    exec ${pythonWithYaml}/bin/python3 -c '
import json, sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
json.dump(data, sys.stdout)
' "$@"
  '';

  queryScript = pkgs.writeShellScript "incus-sync-query" ''
    set -euo pipefail
    JQ="${pkgs.jq}/bin/jq"
    OUTDIR="$1"

    # Query profiles into JSON array
    profiles_json="[]"
    while IFS= read -r url; do
      obj=$(incus query "$url")
      profiles_json=$(printf '%s' "$profiles_json" | $JQ --argjson o "$obj" '. + [$o]')
    done < <(incus query /1.0/profiles | $JQ -r '.[]')
    printf '%s' "$profiles_json" > "$OUTDIR/live-profiles.json"

    # Query instances into JSON array
    instances_json="[]"
    while IFS= read -r url; do
      obj=$(incus query "$url")
      instances_json=$(printf '%s' "$instances_json" | $JQ --argjson o "$obj" '. + [$o]')
    done < <(incus query /1.0/instances | $JQ -r '.[]')
    printf '%s' "$instances_json" > "$OUTDIR/live-instances.json"

    # Also generate YAML for pull mode
    PYTHON="${pythonWithYaml}/bin/python3"
    ENGINE="${yamlEngine}"
    $PYTHON "$ENGINE" generate-profiles < "$OUTDIR/live-profiles.json" > "$OUTDIR/live-profiles.yaml"
    $PYTHON "$ENGINE" generate-instances < "$OUTDIR/live-instances.json" > "$OUTDIR/live-instances.yaml"

    # Bundle live data for semantic diff
    $JQ -n \
      --slurpfile profiles "$OUTDIR/live-profiles.json" \
      --slurpfile instances "$OUTDIR/live-instances.json" \
      '{profiles: $profiles[0], instances: $instances[0]}' > "$OUTDIR/live-bundle.json"
  '';

  incusSyncScript = pkgs.writeShellScriptBin "incus-sync" ''
    set -euo pipefail

    GUM="${pkgs.gum}/bin/gum"
    FIGLET="${pkgs.figlet}/bin/figlet"
    PYTHON="${pythonWithYaml}/bin/python3"
    ENGINE="${yamlEngine}"
    YAML2JSON="${yamlToJson}/bin/incus-yaml-to-json"
    JQ="${pkgs.jq}/bin/jq"

    PROFILES_YAML="/mnt/zpool/code/nix-config/hosts/server-nix/system/incus/profiles.yaml"
    INSTANCES_YAML="/mnt/zpool/code/nix-config/hosts/server-nix/system/incus/instances.yaml"

    WORKDIR=$(mktemp -d)
    trap 'rm -rf "$WORKDIR"' EXIT

    clear
    $GUM style --foreground 86 --border-foreground 86 --border double \
      --align center --width 50 "$($FIGLET -f small "INCUS SYNC")"

    DIRECTION=$($GUM choose "push  (YAML → Runtime)" "pull  (Runtime → YAML)")

    $GUM spin --spinner pulse --title "Querying live Incus state..." -- \
      ${queryScript} "$WORKDIR"

    # Build YAML bundle for semantic diff
    $YAML2JSON "$PROFILES_YAML" > "$WORKDIR/yaml-profiles.json"
    $YAML2JSON "$INSTANCES_YAML" > "$WORKDIR/yaml-instances.json"
    $JQ -n \
      --slurpfile profiles "$WORKDIR/yaml-profiles.json" \
      --slurpfile instances "$WORKDIR/yaml-instances.json" \
      '{profiles: $profiles[0], instances: $instances[0]}' > "$WORKDIR/yaml-bundle.json"

    case "$DIRECTION" in
      push*)
        echo ""
        if $PYTHON "$ENGINE" semantic-diff push \
            "$WORKDIR/live-bundle.json" "$WORKDIR/yaml-bundle.json"; then
          echo ""
          if ! $GUM confirm "Apply YAML config to live Incus?"; then
            $GUM style --foreground 214 "Aborted. No changes made."
            exit 0
          fi
          INCUS_APPLY_MODE=exact incus-declarative-apply
          $GUM style --foreground 82 --border rounded --padding "1 2" \
            "Push complete. Live Incus state updated from YAML."
        else
          echo ""
          $GUM style --foreground 82 --border rounded --padding "1 2" \
            "Already in sync. Nothing to do."
        fi
        ;;

      pull*)
        echo ""
        if $PYTHON "$ENGINE" semantic-diff pull \
            "$WORKDIR/live-bundle.json" "$WORKDIR/yaml-bundle.json"; then
          echo ""
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
        else
          echo ""
          $GUM style --foreground 82 --border rounded --padding "1 2" \
            "Already in sync. Nothing to do."
        fi
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

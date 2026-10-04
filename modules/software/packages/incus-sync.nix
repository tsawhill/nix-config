{ config, pkgs, ... }:

let
  diffEngine = pkgs.writeText "incus-sync-engine.py" ''
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

    def profile_sort_key(name):
        if name == "default":
            return (0, name)
        if name == "nixos-lxc":
            return (1, name)
        return (2, name)

    def fmt_device_inline(dev):
        parts = []
        for k in ordered_device_keys(dev):
            parts.append(f"{k}={dev[k]}")
        return ", ".join(parts)

    def same_value(k, old, new):
        # Incus keeps hwaddr as typed; some live NICs are uppercase.
        if k == "hwaddr":
            return str(old).lower() == str(new).lower()
        return str(old) == str(new)

    def diff_dicts(old, new, indent="  "):
        lines = []
        all_keys = sorted(set(list(old) + list(new)))
        for k in all_keys:
            if k in old and k not in new:
                lines.append(f"{indent}{RED}- {k}: {old[k]}{RESET}")
            elif k not in old and k in new:
                lines.append(f"{indent}{GREEN}+ {k}: {new[k]}{RESET}")
            elif not same_value(k, old[k], new[k]):
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
                dev_changes = diff_dicts(old_devs[dname], new_devs[dname], "      ")
                if dev_changes:
                    lines.append(f"    {dname}:")
                    lines.extend(dev_changes)
        return lines

    def diff_profiles(source, target):
        """Compare profiles. source=live state, target=desired state."""
        lines = []
        all_names = sorted(set(list(source) + list(target)), key=profile_sort_key)
        has_changes = False

        for name in all_names:
            if name in source and name not in target:
                has_changes = True
                lines.append(f"  {RED}{BOLD}{name}{RESET}{RED} (not declared){RESET}")
            elif name not in source and name in target:
                lines.append(f"  {YELLOW}{BOLD}{name}{RESET}{YELLOW} (declared but not in runtime — skipped){RESET}")
            else:
                s, t = source[name], target[name]
                changes = []

                s_desc = s.get("description") or ""
                t_desc = t.get("description") or ""
                if s_desc != t_desc:
                    changes.append(f"    description: {RED}{s_desc}{RESET} → {GREEN}{t_desc}{RESET}")

                changes.extend(diff_dicts(s.get("config") or {}, t.get("config") or {}, "    "))
                changes.extend(diff_devices(s.get("devices") or {}, t.get("devices") or {}))

                if changes:
                    has_changes = True
                    lines.append(f"  {BOLD}{name}{RESET}")
                    lines.extend(changes)

        if not has_changes:
            lines.append(f"  {DIM}No changes.{RESET}")

        return has_changes, "\n".join(lines)

    def diff_instances(source, target):
        """Compare instances. source=live state, target=desired state."""
        lines = []
        all_names = sorted(set(list(source) + list(target)))
        has_changes = False

        for name in all_names:
            if name in source and name not in target:
                has_changes = True
                lines.append(f"  {RED}{BOLD}{name}{RESET}{RED} (not declared){RESET}")
            elif name not in source and name in target:
                lines.append(f"  {YELLOW}{BOLD}{name}{RESET}{YELLOW} (declared but not created — skipped){RESET}")
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
                changes.extend(diff_dicts(s_cfg, t_cfg, "    "))
                changes.extend(diff_devices(s.get("devices") or {}, t.get("devices") or {}))

                if changes:
                    has_changes = True
                    lines.append(f"  {BOLD}{name}{RESET}")
                    lines.extend(changes)

        if not has_changes:
            lines.append(f"  {DIM}No changes.{RESET}")

        return has_changes, "\n".join(lines)

    def main():
        if len(sys.argv) != 3:
            print("usage: engine.py <live.json> <registry.json>", file=sys.stderr)
            sys.exit(2)

        with open(sys.argv[1]) as f:
            live = json.load(f)
        with open(sys.argv[2]) as f:
            desired = json.load(f)

        live_profiles = {p["name"]: p for p in live.get("profiles", [])}
        live_instances = {i["name"]: i for i in live.get("instances", [])}

        print(f"{BOLD}{CYAN}═══ Profile Changes (live → Nix) ═══{RESET}")
        p_changed, p_output = diff_profiles(live_profiles, desired.get("profiles", {}))
        print(p_output)
        print()
        print(f"{BOLD}{CYAN}═══ Instance Changes (live → Nix) ═══{RESET}")
        i_changed, i_output = diff_instances(live_instances, desired.get("instances", {}))
        print(i_output)

        sys.exit(0 if (p_changed or i_changed) else 1)

    main()
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

    $JQ -n \
      --slurpfile profiles "$OUTDIR/live-profiles.json" \
      --slurpfile instances "$OUTDIR/live-instances.json" \
      '{profiles: $profiles[0], instances: $instances[0]}' > "$OUTDIR/live-bundle.json"
  '';

  incusSyncScript = pkgs.writeShellScriptBin "incus-sync" ''
    set -euo pipefail

    GUM="${pkgs.gum}/bin/gum"
    FIGLET="${pkgs.figlet}/bin/figlet"
    PYTHON="${pkgs.python3}/bin/python3"
    ENGINE="${diffEngine}"
    REGISTRY="${config.my.incusDeclarative.registry}"

    WORKDIR=$(mktemp -d)
    trap 'rm -rf "$WORKDIR"' EXIT

    clear
    $GUM style --foreground 86 --border-foreground 86 --border double \
      --align center --width 50 "$($FIGLET -f small "INCUS SYNC")"

    $GUM spin --spinner pulse --title "Querying live Incus state..." -- \
      ${queryScript} "$WORKDIR"

    echo ""
    if $PYTHON "$ENGINE" "$WORKDIR/live-bundle.json" "$REGISTRY"; then
      echo ""
      if ! $GUM confirm "Apply the Nix registry to live Incus (exact mode)?"; then
        $GUM style --foreground 214 "Aborted. No changes made."
        exit 0
      fi
      INCUS_APPLY_MODE=exact incus-declarative-apply
      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Live Incus state updated from the Nix registry."
    else
      echo ""
      $GUM style --foreground 82 --border rounded --padding "1 2" \
        "Already in sync. Nothing to do."
    fi
  '';
in
{
  environment.systemPackages = [
    pkgs.gum
    pkgs.figlet
    pkgs.jq
    incusSyncScript
  ];
}

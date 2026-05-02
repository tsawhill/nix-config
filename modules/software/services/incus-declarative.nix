{ config, lib, pkgs, ... }:

let
  cfg = config.my.incusDeclarative;

  strAttrs = lib.types.attrsOf lib.types.str;

  deviceType = lib.types.attrsOf lib.types.str;

  profileType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      config = lib.mkOption {
        type = strAttrs;
        default = { };
      };
      devices = lib.mkOption {
        type = lib.types.attrsOf deviceType;
        default = { };
      };
    };
  };

  instanceType = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [
          "container"
          "virtual-machine"
        ];
      };
      profiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      config = lib.mkOption {
        type = strAttrs;
        default = { };
      };
      devices = lib.mkOption {
        type = lib.types.attrsOf deviceType;
        default = { };
      };
    };
  };

  desired = pkgs.writeText "incus-declarative.json" (
    builtins.toJSON {
      mode = cfg.mode;
      inherit (cfg) profiles instances;
    }
  );

  applyScript = pkgs.writeShellScript "apply-declarative-incus" ''
    set -uo pipefail

    desired=${lib.escapeShellArg desired}
    mode=$(${pkgs.jq}/bin/jq -r '.mode' "$desired")

    log() {
      echo "[incus-declarative] $*"
    }

    warn() {
      echo "[incus-declarative] WARN: $*" >&2
    }

    json_keys() {
      ${pkgs.jq}/bin/jq -r "$1 | keys[]" "$desired"
    }

    json_get() {
      ${pkgs.jq}/bin/jq -r "$1" "$desired"
    }

    size_to_bytes() {
      case "$1" in
        *GiB)
          n="''${1%GiB}"
          echo $((n * 1024 * 1024 * 1024))
          ;;
        *MiB)
          n="''${1%MiB}"
          echo $((n * 1024 * 1024))
          ;;
        "")
          echo 0
          ;;
        *)
          warn "cannot parse size '$1'; treating it as 0"
          echo 0
          ;;
      esac
    }

    profile_exists() {
      incus profile show "$1" >/dev/null 2>&1
    }

    instance_exists() {
      incus info "$1" >/dev/null 2>&1
    }

    device_args() {
      local base_expr="$1"
      local key value
      while IFS= read -r key; do
        [ "$key" = "type" ] && continue
        value=$(json_get "$base_expr[$(printf '%s' "$key" | ${pkgs.jq}/bin/jq -Rsa .)]")
        printf '%s=%s\n' "$key" "$value"
      done < <(json_keys "$base_expr")
    }

    apply_profile_device() {
      local profile="$1"
      local dev="$2"
      local expr=".profiles[$(printf '%s' "$profile" | ${pkgs.jq}/bin/jq -Rsa .)].devices[$(printf '%s' "$dev" | ${pkgs.jq}/bin/jq -Rsa .)]"
      local type
      type=$(json_get "$expr.type")

      if ! incus profile device get "$profile" "$dev" type >/dev/null 2>&1; then
        local args=()
        while IFS= read -r kv; do
          args+=("$kv")
        done < <(device_args "$expr")
        log "adding profile device $profile/$dev"
        if ! incus profile device add "$profile" "$dev" "$type" "''${args[@]}"; then
          warn "failed to add profile device $profile/$dev"
        fi
        return
      fi

      local key desired_value current_value
      while IFS= read -r key; do
        [ "$key" = "type" ] && continue
        desired_value=$(json_get "$expr[$(printf '%s' "$key" | ${pkgs.jq}/bin/jq -Rsa .)]")
        current_value=$(incus profile device get "$profile" "$dev" "$key" 2>/dev/null || true)
        if [ "$current_value" != "$desired_value" ]; then
          log "setting profile device $profile/$dev $key=$desired_value"
          if ! incus profile device set "$profile" "$dev" "$key" "$desired_value"; then
            warn "failed to set profile device $profile/$dev $key"
          fi
        fi
      done < <(json_keys "$expr")
    }

    apply_profile() {
      local profile="$1"
      local expr=".profiles[$(printf '%s' "$profile" | ${pkgs.jq}/bin/jq -Rsa .)]"

      if ! profile_exists "$profile"; then
        log "creating profile $profile"
        if ! incus profile create "$profile"; then
          warn "failed to create profile $profile"
          return
        fi
      fi

      local key desired_value current_value
      while IFS= read -r key; do
        desired_value=$(json_get "$expr.config[$(printf '%s' "$key" | ${pkgs.jq}/bin/jq -Rsa .)]")
        current_value=$(incus profile get "$profile" "$key" 2>/dev/null || true)
        if [ "$current_value" != "$desired_value" ]; then
          log "setting profile $profile config $key=$desired_value"
          if ! incus profile set "$profile" "$key" "$desired_value"; then
            warn "failed to set profile $profile config $key"
          fi
        fi
      done < <(json_keys "$expr.config")

      while IFS= read -r dev; do
        apply_profile_device "$profile" "$dev"
      done < <(json_keys "$expr.devices")
    }

    profile_path_conflicts_instance_devices() {
      local instance="$1"
      local profile="$2"
      local profile_expr=".profiles[$(printf '%s' "$profile" | ${pkgs.jq}/bin/jq -Rsa .)]"
      local paths
      paths=$(json_get "$profile_expr.devices | to_entries[] | select(.value.type == \"disk\") | .value.path")
      [ -n "$paths" ] || return 1

      local live_paths
      live_paths=$(incus query "/1.0/instances/$instance" \
        | ${pkgs.jq}/bin/jq -r '.devices | to_entries[] | select(.value.type == "disk" and .key != "root" and .key != "nix-store") | .value.path')

      local path
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        if printf '%s\n' "$live_paths" | grep -Fxq "$path"; then
          warn "$instance has local disk at $path; not adding profile $profile until cleanup removes the local mount"
          return 0
        fi
      done <<< "$paths"

      return 1
    }

    ensure_instance_profile() {
      local instance="$1"
      local profile="$2"
      if incus query "/1.0/instances/$instance" \
        | ${pkgs.jq}/bin/jq -e --arg profile "$profile" '.profiles | index($profile)' >/dev/null; then
        return
      fi

      if profile_path_conflicts_instance_devices "$instance" "$profile"; then
        return
      fi

      log "adding profile $profile to $instance"
      if ! incus profile add "$instance" "$profile"; then
        warn "failed to add profile $profile to $instance"
      fi
    }

    apply_instance_device_property() {
      local instance="$1"
      local dev="$2"
      local key="$3"
      local desired_value="$4"

      if [ "$dev" = "root" ] && [ "$key" = "size" ]; then
        local target_bytes usage_bytes
        target_bytes=$(size_to_bytes "$desired_value")
        usage_bytes=$(incus query "/1.0/instances/$instance/state" \
          | ${pkgs.jq}/bin/jq -r '.disk.root.usage // 0' 2>/dev/null || echo 0)
        if [ "$target_bytes" -gt 0 ] && [ "$usage_bytes" -gt "$target_bytes" ]; then
          warn "$instance root usage $usage_bytes bytes exceeds target $desired_value; skipping root shrink"
          return
        fi
      fi

      local current_value
      current_value=$(incus config device get "$instance" "$dev" "$key" 2>/dev/null || true)
      if [ "$current_value" != "$desired_value" ]; then
        log "setting instance device $instance/$dev $key=$desired_value"
        if ! incus config device set "$instance" "$dev" "$key" "$desired_value"; then
          warn "failed to set instance device $instance/$dev $key"
        fi
      fi
    }

    apply_instance_device() {
      local instance="$1"
      local dev="$2"
      local expr=".instances[$(printf '%s' "$instance" | ${pkgs.jq}/bin/jq -Rsa .)].devices[$(printf '%s' "$dev" | ${pkgs.jq}/bin/jq -Rsa .)]"
      local type
      type=$(json_get "$expr.type")

      if ! incus config device get "$instance" "$dev" type >/dev/null 2>&1; then
        local args=()
        while IFS= read -r kv; do
          args+=("$kv")
        done < <(device_args "$expr")
        log "adding instance device $instance/$dev"
        if ! incus config device add "$instance" "$dev" "$type" "''${args[@]}"; then
          warn "failed to add instance device $instance/$dev"
        fi
        return
      fi

      local key desired_value
      while IFS= read -r key; do
        [ "$key" = "type" ] && continue
        desired_value=$(json_get "$expr[$(printf '%s' "$key" | ${pkgs.jq}/bin/jq -Rsa .)]")
        apply_instance_device_property "$instance" "$dev" "$key" "$desired_value"
      done < <(json_keys "$expr")
    }

    apply_instance() {
      local instance="$1"
      local expr=".instances[$(printf '%s' "$instance" | ${pkgs.jq}/bin/jq -Rsa .)]"

      if ! instance_exists "$instance"; then
        warn "desired instance $instance is missing; non-destructive mode will not create it"
        return
      fi

      local desired_type live_type
      desired_type=$(json_get "$expr.type")
      live_type=$(incus query "/1.0/instances/$instance" | ${pkgs.jq}/bin/jq -r '.type')
      if [ "$desired_type" != "$live_type" ]; then
        warn "$instance type drift: live=$live_type desired=$desired_type"
      fi

      local key desired_value current_value
      while IFS= read -r key; do
        desired_value=$(json_get "$expr.config[$(printf '%s' "$key" | ${pkgs.jq}/bin/jq -Rsa .)]")
        current_value=$(incus config get "$instance" "$key" 2>/dev/null || true)
        if [ "$current_value" != "$desired_value" ]; then
          log "setting instance $instance config $key=$desired_value"
          if ! incus config set "$instance" "$key" "$desired_value"; then
            warn "failed to set instance $instance config $key"
          fi
        fi
      done < <(json_keys "$expr.config")

      while IFS= read -r profile; do
        ensure_instance_profile "$instance" "$profile"
      done < <(json_get "$expr.profiles[]")

      while IFS= read -r dev; do
        apply_instance_device "$instance" "$dev"
      done < <(json_keys "$expr.devices")

      local raw_idmap
      raw_idmap=$(incus config get "$instance" raw.idmap 2>/dev/null || true)
      if [ -n "$raw_idmap" ] && ! json_get "$expr.config | has(\"raw.idmap\")" | grep -qx true; then
        if [ "$mode" = "exact" ]; then
          log "unsetting undeclared raw.idmap on $instance"
          incus config unset "$instance" raw.idmap || warn "failed to unset raw.idmap on $instance"
        else
          warn "$instance has undeclared raw.idmap=$raw_idmap"
        fi
      fi
    }

    report_extra_live_state() {
      local live

      while IFS= read -r live; do
        [ -n "$live" ] || continue
        if ! ${pkgs.jq}/bin/jq -e --arg name "$live" '.instances | has($name)' "$desired" >/dev/null; then
          warn "live instance $live is not declared"
        fi
      done < <(incus list -c n --format csv)

      while IFS= read -r live; do
        [ -n "$live" ] || continue
        if ! ${pkgs.jq}/bin/jq -e --arg name "$live" '.profiles | has($name)' "$desired" >/dev/null; then
          warn "live profile $live is not declared"
        fi
      done < <(incus profile list --format csv | cut -d, -f1)

      local instance dev
      while IFS= read -r instance; do
        [ -n "$instance" ] || continue
        while IFS= read -r dev; do
          [ -n "$dev" ] || continue
          if ! ${pkgs.jq}/bin/jq -e --arg i "$instance" --arg d "$dev" '.instances[$i].devices | has($d)' "$desired" >/dev/null; then
            if [ "$mode" = "exact" ]; then
              log "removing undeclared local disk $instance/$dev"
              incus config device remove "$instance" "$dev" || warn "failed to remove local disk $instance/$dev"
            else
              warn "$instance has undeclared local disk device $dev"
            fi
          fi
        done < <(incus query "/1.0/instances/$instance" \
          | ${pkgs.jq}/bin/jq -r '.devices | to_entries[] | select(.value.type == "disk" and .key != "root" and .key != "nix-store") | .key')
      done < <(json_keys ".instances")
    }

    log "applying Incus desired state in $mode mode"

    while IFS= read -r profile; do
      apply_profile "$profile"
    done < <(json_keys ".profiles")

    while IFS= read -r instance; do
      apply_instance "$instance"
    done < <(json_keys ".instances")

    report_extra_live_state

    log "done"
  '';
in
{
  options.my.incusDeclarative = {
    enable = lib.mkEnableOption "declarative Incus profiles and instance settings";

    mode = lib.mkOption {
      type = lib.types.enum [
        "non-destructive"
        "exact"
      ];
      default = "non-destructive";
      description = "How aggressively to reconcile live Incus state against the registry.";
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf profileType;
      default = { };
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf instanceType;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.jq
      (pkgs.writeShellScriptBin "incus-declarative-apply" ''
        exec ${applyScript}
      '')
    ];

    systemd.services.incus-declarative-apply = {
      description = "Apply declarative Incus profiles and instance settings";
      after = [ "incus.service" ];
      requires = [ "incus.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        config.virtualisation.incus.package
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.jq
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${applyScript}
      '';
    };
  };
}

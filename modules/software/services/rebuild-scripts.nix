{ config, pkgs, ... }:

let
  # --- 1. HOST DEFINITIONS ---
  dailyHosts = [
    "local-nginx-nix"
    "remote-nginx-nix"
  ];
  weeklyHosts = [
    "build-nix"
    "vaultwarden-nix"
    "unbound-vpn-na-nix"
    "adguard-nix"
    "nextcloud-nix"
    "jellyseerr-nix"
    "jellyfin-nix"
    "gotify-nix"
    "llm-nix"
    "arrs-nix"
    "socks5-vpn-eu-nix"
    "acme-nix"
  ];
  monthlyHosts = [
    "unifi-nix"
    "samba-nix"
    "immich-nix"
    "pufferpanel-nix"
    "deluge-nix"
  ];
  noPushHosts = [ ];

  flakePath = "path:///mnt/zpool/nixosconfigs";

  # --- 2. UNIFIED LOGIC SCRIPT ---
  rebuildManager = pkgs.writeShellApplication {
    name = "rebuild-manager";
    runtimeInputs = [
      pkgs.nix
      pkgs.nixos-rebuild
      pkgs.openssh
      pkgs.gotify-cli
    ];
    text = ''
      # Configuration
      FLAKE_URI="${flakePath}"
      NO_PUSH_LIST=(${builtins.concatStringsSep " " (map (h: "\"${h}\"") noPushHosts)})

      # Tracking Arrays
      SUCCESS_HOSTS=()
      FAILED_HOSTS=()

      # Argument Parsing
      MODE=""
      TASK_NAME="Manual"
      NEXT_SERVICE=""

      if [ $# -lt 1 ]; then
        echo "Usage: rebuild-manager <mode> [options] [hosts...]"
        exit 1
      fi

      MODE="$1"
      shift

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --name) TASK_NAME="$2"; shift 2 ;;
          --service) NEXT_SERVICE="$2"; shift 2 ;;
          -*) echo "Unknown option $1"; exit 1 ;;
          *) break ;;
        esac
      done

      HOSTS=("$@")

      # Helper Functions
      send_summary() {
        local status_icon="✅"
        if [ ''${#FAILED_HOSTS[@]} -gt 0 ]; then
          status_icon="❌"
        fi

        local content=""
        if [ ''${#FAILED_HOSTS[@]} -gt 0 ]; then
          content+="Build failure for:\n"
          for h in "''${FAILED_HOSTS[@]}"; do content+="$h\n"; done
          content+="\n"
        fi
        if [ ''${#SUCCESS_HOSTS[@]} -gt 0 ]; then
          content+="Build success for:\n"
          for h in "''${SUCCESS_HOSTS[@]}"; do content+="$h\n"; done
        fi

        gotify push -t "''${status_icon} ''${TASK_NAME} build summary" -p 5 "''${content}"
      }

      update_flake() {
        echo "--- Updating Flake ---"
        if nix flake update --flake "$FLAKE_URI"; then
          echo "✅ Flake update success"
        else
          echo "❌ Flake update failed"
          exit 1
        fi
      }

      build_host() {
        local host="$1"
        local flake_url="$FLAKE_URI#nixosConfigurations.''${host}.config.system.build.toplevel"
        local profile_path="/nix/var/nix/profiles/per-host/''${host}"

        echo "--- Building: $host ---"
        
        # Create separate temp files for the Store Path and the Build Logs
        PATH_LOG=$(mktemp)
        ERROR_LOG=$(mktemp)

        # Redirect stdout (> path) and stderr (2> logs) separately
        if nix build "$flake_url" --print-out-paths --no-link > "$PATH_LOG" 2> "$ERROR_LOG"; then
          # SUCCESS: The path log will only contain the clean /nix/store/... path
          STORE_PATH=$(cat "$PATH_LOG")
          
          # Optional: Print warnings to console
          cat "$ERROR_LOG"

          nix-env --profile "$profile_path" --set "$STORE_PATH"
          nix-env --profile "$profile_path" --delete-generations +5
          echo "✅ Build created for $host"
          SUCCESS_HOSTS+=("$host")
          
          rm "$PATH_LOG" "$ERROR_LOG"
          return 0 
        else
          # FAILURE: Use the error log for the notification
          echo "❌ Failed to build $host"
          
          # Print logs to stdout for debugging
          cat "$ERROR_LOG"

          ERROR_SUMMARY=$(tail -n 20 "$ERROR_LOG")
          FAILED_HOSTS+=("$host")
          
          gotify push -t "❌ CRITICAL: $host Build failed" \
                  -p 10 \
                 "Build failed for $host. Last lines of log: $ERROR_SUMMARY"
                 
          rm "$PATH_LOG" "$ERROR_LOG"
          return 0 
        fi
      }

      push_host() {
        local host="$1"
        local profile_path="/nix/var/nix/profiles/per-host/''${host}"
        local current_hostname
        current_hostname=$(hostname)

        for skip in "''${NO_PUSH_LIST[@]}";
        do
          if [[ "$host" == "$skip" ]];
          then
            echo "⏭️ Skipping push for: $host (noPushHosts)"
            return 0
          fi
        done

        if [[ -L "$profile_path" ]];
        then
          echo "🚀 Pushing: $host"
          
          # --- FIX START: Handle Self-Update ---
          if [[ "$host" == "$current_hostname" ]] || [[ "$host" == "build-nix" ]]; then
             echo "🔄 Self-update detected. Using 'boot' to prevent service interruption."
             # Use 'boot' for self to avoid killing this running script
             # Also drop --target-host to run directly locally
             if nixos-rebuild boot --flake "$FLAKE_URI#$host"; 
             then
                rm "$profile_path"
                echo "✅ Self-update (boot) successful: $host"
                return 0
             else
                echo "❌ Failed to boot-update $host"
                return 1
             fi
          fi
          # --- FIX END ---

          if nixos-rebuild switch --flake "$FLAKE_URI#$host" --target-host "root@$host.lan";
          then
             rm "$profile_path"
             echo "✅ Push successful: $host"
          else
             echo "❌ Failed to push $host"
             return 1
          fi
        else
          echo "ℹ️ No new build profile found for $host. Skipping."
        fi
      }


      # --- MAIN EXECUTION ---
      if [[ "$MODE" == "build" || "$MODE" == "all" ]]; then
        update_flake
        for host in "''${HOSTS[@]}"; do
          build_host "$host"
        done
        
        # Only send summary during scheduled builds
        send_summary

        if [[ "$MODE" == "build" && -n "$NEXT_SERVICE" ]]; then
           echo "--- Triggering Push Service ---"
           systemctl start "$NEXT_SERVICE"
        fi
      fi

      if [[ "$MODE" == "push" || "$MODE" == "all" ]]; then
        # DECIDE TARGETS:
        # If we just built ("all"), ONLY push hosts that succeeded.
        # If we are only pushing ("push"), attempt everything the user asked for.
        TARGETS_TO_PUSH=()
        if [[ "$MODE" == "all" ]]; then
            TARGETS_TO_PUSH=("''${SUCCESS_HOSTS[@]}")
        else
            TARGETS_TO_PUSH=("''${HOSTS[@]}")
        fi

        PUSH_ERRORS=0
        
        for host in "''${TARGETS_TO_PUSH[@]}"; do
          # We use 'if !' to capture failure without crashing the script (due to set -e)
          if ! push_host "$host"; then
             PUSH_ERRORS=1
          fi
        done
        
        # If any individual push failed, fail the whole job at the very end
        # so Systemd knows to retry (after the 18h delay).
        if [[ "$PUSH_ERRORS" -eq 1 ]]; then
           echo "❌ Some hosts failed to push. Exiting with error."
           exit 1
        fi
      fi

      if [[ "$MODE" == "notify" ]]; then
        gotify push -t "❌ CRITICAL: $TASK_NAME Push Failed" -p 10 "Deployment failed for 18 consecutive hours."
      fi
    '';
  };

  # --- 3. MANUAL COMMAND ALIAS ---
  rebuildHost = pkgs.writeShellScriptBin "rebuild-Host" ''
    exec ${rebuildManager}/bin/rebuild-manager all --name "Manual" "$@"
  '';

  # --- 4. TASK GENERATOR ---
  mkRebuildTask = name: interval: hosts: {
    inherit interval;
    buildService = {
      description = "${name} Build Task";
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${rebuildManager}/bin/rebuild-manager build --name \"${name}\" --service \"rebuild-push-${name}.service\" ${builtins.concatStringsSep " " hosts}";
      };
    };
    pushService = {
      description = "${name} Push Task (Retries 18h)";
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Restart = "on-failure";
        RestartSec = "1h";
        StartLimitBurst = 18;
        StartLimitIntervalSec = 66600;
        ExecStart = "${rebuildManager}/bin/rebuild-manager push --name \"${name}\" ${builtins.concatStringsSep " " hosts}";
        ExecStopPost = pkgs.writeShellScript "notify-on-limit" ''
          if [ "$SERVICE_RESULT" = "start-limit-hit" ]; then
            ${rebuildManager}/bin/rebuild-manager notify --name "${name}"
          fi
        '';
      };
    };
    notifyService = {
      description = "${name} Failure Notification";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${rebuildManager}/bin/rebuild-manager notify --name \"${name}\"";
      };
    };
    timer = {
      description = "Run ${name} Build Script";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = interval;
        Persistent = true;
        Unit = "rebuild-build-${name}.service";
      };
    };
  };

  # --- 5. TASK INSTANCES ---
  daily = mkRebuildTask "Daily" "Sun,Mon..Fri *-*-* 00:00" dailyHosts;
  weekly = mkRebuildTask "Weekly" "Sat *-*-8..31 00:00" (dailyHosts ++ weeklyHosts);
  monthly = mkRebuildTask "Monthly" "Sat *-*-1..7 00:00" (dailyHosts ++ weeklyHosts ++ monthlyHosts);
  self = mkRebuildTask "Self" "Sat *-*-* 01:00" [ "build-nix" ];

in
{
  environment.systemPackages = [
    rebuildManager
    rebuildHost
  ];

  systemd.services = {
    "rebuild-build-Daily" = daily.buildService;
    "rebuild-push-Daily" = daily.pushService;
    "rebuild-notify-Daily" = daily.notifyService;

    "rebuild-build-Weekly" = weekly.buildService;
    "rebuild-push-Weekly" = weekly.pushService;
    "rebuild-notify-Weekly" = weekly.notifyService;

    "rebuild-build-Monthly" = monthly.buildService;
    "rebuild-push-Monthly" = monthly.pushService;
    "rebuild-notify-Monthly" = monthly.notifyService;

    "rebuild-build-Self" = self.buildService;
    "rebuild-push-Self" = self.pushService;
    "rebuild-notify-Self" = self.notifyService;
  };

  systemd.timers = {
    "rebuild-Daily" = daily.timer;
    "rebuild-Weekly" = weekly.timer;
    "rebuild-Monthly" = monthly.timer;
    "rebuild-Self" = self.timer;
  };
}

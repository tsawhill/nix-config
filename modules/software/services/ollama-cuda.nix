{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "0.0.0.0";
    openFirewall = true;
    # Pulled by ollama-model-loader.service, so a wiped model store heals on
    # the next deploy. qwen2.5-coder:7b is ~4.7 GiB at Q4_K_M, which leaves the
    # 2070 Super's 8 GiB enough room for deployctl's 16k context window.
    loadModels = [ "qwen2.5-coder:7b" ];
  };

  # Ollama probes for GPUs exactly once, when the process starts, and keeps
  # whatever it found for the rest of that process's life. When the probe times
  # out ("llama-server GPU discovery watchdog timed out") it registers a
  # CPU-only device list and never retries. That state is invisible until
  # something asks for inference, and this container has 2 GiB of RAM, so a
  # CPU load does not merely run slowly: it exhausts the container and is
  # OOM-killed. One such probe failure left ollama serving from the CPU for
  # four days.
  systemd.services.ollama.serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = lib.mkForce 10;
  };
  # An OOM kill must never leave ollama stopped for good.
  systemd.services.ollama.unitConfig.StartLimitIntervalSec = lib.mkForce 0;

  systemd.services.ollama-gpu-guard = {
    description = "Restart ollama until it discovers the GPU";
    wants = [ "ollama.service" ];
    after = [ "ollama.service" ];
    # Settle the GPU question before the loader spends bandwidth pulling models.
    before = [ "ollama-model-loader.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      config.systemd.package
      pkgs.gnugrep
      pkgs.coreutils
    ];
    # Deliberately not RemainAfterExit: the unit must fall back to inactive so
    # the timer below can trigger it again.
    serviceConfig.Type = "oneshot";
    script = ''
      set -uo pipefail

      # Scoping the journal to the current MainPID is what makes this reliable:
      # it reads the probe result of the running process, not a stale one.
      probe_result() {
        local pid="$1"
        journalctl _PID="$pid" --no-pager 2>/dev/null \
          | grep -o 'msg="inference compute".*' | tail -1
      }

      for attempt in $(seq 1 5); do
        pid="$(systemctl show -p MainPID --value ollama)"

        # The probe runs a few seconds after start; wait for it to be logged.
        for _ in $(seq 1 60); do
          [ -n "$(probe_result "$pid")" ] && break
          sleep 1
          pid="$(systemctl show -p MainPID --value ollama)"
        done

        result="$(probe_result "$pid")"
        if printf '%s' "$result" | grep -q 'library=CUDA'; then
          echo "ollama discovered the GPU (pid $pid)"
          exit 0
        fi

        echo "ollama came up without a GPU (pid $pid): ''${result:-no probe logged}"
        echo "restarting ollama to re-probe (attempt $attempt/5)"
        # --no-block avoids deadlocking this unit against ollama's restart job.
        systemctl --no-block restart ollama
        sleep 15
      done

      echo "ollama never discovered the GPU; refusing to leave it serving from the CPU" >&2
      exit 1
    '';
  };

  # Catches the case where ollama restarts on its own and loses the probe.
  systemd.timers.ollama-gpu-guard = {
    description = "Re-check that ollama is still using the GPU";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "15min";
      Unit = "ollama-gpu-guard.service";
    };
  };
}

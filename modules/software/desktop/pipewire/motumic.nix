{
  lib,
  config,
  pkgs,
  ...
}:
#
# Native PipeWire processing chain for the MOTU M2 microphone.
#
# All plugins use LADSPA with absolute nix store paths — no LV2_PATH
# discovery needed, works correctly in socket-activated pipewire.service.
#
# When my.desktop.audio.mics.virtual is also enabled, the loopback is skipped —
# the filter chain output IS mic_input. Apps connect to it via the pipewire-pulse
# routing rule, same mechanism as the working output sinks.
#
{
  options.my.desktop.audio.motuMic.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable native PipeWire DSP chain for the MOTU M2 microphone.";
  };

  config = lib.mkIf config.my.desktop.audio.motuMic.enable {

    services.pipewire = {

      ##############################################################
      # Filter chain: MOTU M2 mic → DSP → virtual source
      ##############################################################
      extraConfig.pipewire."95-motu-mic"."context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "MOTU M2 Mic (Processed)";
            "media.name" = "MOTU M2 Mic Processed";
            # 480 samples required by rnnoise's fixed frame size.
            "node.latency" = "480/48000";

            "filter.graph" = {
              "nodes" = [
                {
                  type = "ladspa";
                  name = "gate";
                  plugin = "lsp-plugins-ladspa";
                  label = "http://lsp-plug.in/plugins/ladspa/gate_mono";
                  control = {
                    # Thresholds below are absolute dBFS and were measured at the
                    # M2's current hardware gain (fan floor peaks -46 dB, speech
                    # peaks -16 dB). MOVING THE GAIN KNOB INVALIDATES THEM — remeasure
                    # with: ffmpeg -f pulse -i <m2 source> -t 5 \
                    #   -af "pan=mono|c0=c0,volumedetect" -f null -
                    #
                    # -38 dBFS: 8 dB above the fan's peak, below conversational speech.
                    "Curve threshold (G)" = 0.0126;
                    "Attack (ms)" = 5.0;
                    "Release (ms)" = 120.0;
                    # -60 dB when closed — effectively silent between phrases.
                    "Reduction (G)" = 0.001;
                    # Hysteresis OFF deliberately. It latches: the gate opens on
                    # speech and won't close until the signal drops below the
                    # separate (lower) hysteresis threshold, which the fan now sits
                    # above — so airflow held the gate open indefinitely. Equal
                    # open/close points plus the release time avoid that entirely.
                    "Hysteresis" = 0.0;
                    "High-pass filter mode" = 1.0;
                    # Sidechain deaf below 400 Hz so fan/rumble can't hold the gate
                    # open. This buys real extra margin — fan energy is mostly low.
                    "High-pass filter frequency (Hz)" = 400.0;
                    "Sidechain mode" = 1.0;
                    # Unity, so the threshold above reads directly as dBFS.
                    "Sidechain preamp (G)" = 1.0;
                  };
                }
                {
                  type = "builtin";
                  name = "hpf";
                  label = "bq_highpass";
                  control = {
                    "Freq" = 100.0;
                    "Q" = 0.707;
                  };
                }
                {
                  type = "ladspa";
                  name = "rnnoise";
                  plugin = "librnnoise_ladspa";
                  label = "noise_suppressor_mono";
                  control = {
                    "VAD Threshold (%)" = 95.0;
                    "VAD Grace Period (ms)" = 100.0;
                    # Bumped to protect word onsets from the more aggressive VAD.
                    "Retroactive VAD Grace (ms)" = 30.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq_presence";
                  label = "bq_peaking";
                  control = {
                    "Freq" = 3000.0;
                    "Q" = 1.0;
                    "Gain" = 2.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq_air";
                  label = "bq_highshelf";
                  control = {
                    "Freq" = 10000.0;
                    "Q" = 0.707;
                    "Gain" = 2.0;
                  };
                }
                {
                  type = "ladspa";
                  name = "compressor";
                  plugin = "lsp-plugins-ladspa";
                  label = "http://lsp-plug.in/plugins/ladspa/compressor_mono";
                  control = {
                    "Sidechain mode" = 1.0;
                    "Attack threshold (G)" = 0.178;
                    "Ratio" = 3.0;
                    "Knee (G)" = 0.5;
                    "Attack time (ms)" = 5.0;
                    "Release time (ms)" = 150.0;
                    "Makeup gain (G)" = 2.0;
                  };
                }
                {
                  type = "ladspa";
                  name = "limiter";
                  plugin = "lsp-plugins-ladspa";
                  label = "http://lsp-plug.in/plugins/ladspa/limiter_mono";
                  control = {
                    "Threshold (G)" = 0.891;
                    "Lookahead (ms)" = 1.5;
                  };
                }
              ];
              "links" = [
                {
                  output = "gate:Output";
                  input = "hpf:In";
                }
                {
                  output = "hpf:Out";
                  input = "rnnoise:Input";
                }
                {
                  output = "rnnoise:Output";
                  input = "eq_presence:In";
                }
                {
                  output = "eq_presence:Out";
                  input = "eq_air:In";
                }
                {
                  output = "eq_air:Out";
                  input = "compressor:Input";
                }
                {
                  output = "compressor:Output";
                  input = "limiter:Input";
                }
              ];
              "inputs" = [ "gate:Input" ];
              "outputs" = [ "limiter:Output" ];
            };

            "capture.props" = {
              "node.name" = "motu_mic_capture";
              "audio.position" = [ "FL" ];
              "node.passive" = true;
            };

            "playback.props" = {
              "node.name" = "mic_input";
              "node.description" = "Mic Input";
              "media.class" = "Audio/Source";
              "audio.position" = [ "MONO" ];
              "priority.session" = 2200;
            };

          }; # /args
        }
      ]; # /context.modules

    }; # /services.pipewire
  };
}

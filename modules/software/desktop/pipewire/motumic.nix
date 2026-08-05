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
                    "Curve threshold (G)" = 0.20;
                    "Attack (ms)" = 5.0;
                    "Release (ms)" = 120.0;
                    # -60 dB when closed — effectively silent between phrases.
                    "Reduction (G)" = 0.001;
                    "Hysteresis" = 1.0;
                    "Hysteresis threshold (G)" = 0.05;
                    "High-pass filter mode" = 1.0;
                    # Sidechain deaf below 400 Hz so fan/rumble can't hold the gate open.
                    "High-pass filter frequency (Hz)" = 400.0;
                    "Sidechain mode" = 1.0;
                    "Sidechain preamp (G)" = 2.0;
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

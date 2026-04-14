{
  lib,
  config,
  pkgs,
  ...
}:
#
# Native PipeWire processing chain for the PreSonus Studio 24c microphone.
# Replicates the active EasyEffects input chain:
#
#   [gate]       → LSP SC Gate Mono (LADSPA)
#   [deepfilternet] → RNNoise (LADSPA, closest available native equivalent)
#   [compressor] → LSP SC Compressor Mono (LADSPA)
#   [speex/reverb] → bypassed in EasyEffects, skipped
#
# All plugins use LADSPA with absolute nix store paths — no LV2_PATH
# discovery needed, works correctly in socket-activated pipewire.service.
#
# When my.desktop.audio.mics.virtual is also enabled, the loopback is skipped —
# the filter chain output IS mic_input. Apps connect to it via the pipewire-pulse
# routing rule, same mechanism as the working output sinks.
#
{
  options.my.desktop.audio.presonusMic.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable native PipeWire DSP chain for the PreSonus Studio 24c microphone.";
  };

  config = lib.mkIf config.my.desktop.audio.presonusMic.enable {

    services.pipewire = {

      ##############################################################
      # Filter chain: PreSonus mic → DSP → virtual source
      ##############################################################
      extraConfig.pipewire."95-presonus-mic"."context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "PreSonus Mic (Processed)";
            "media.name" = "PreSonus Mic Processed";
            # 480 samples required by rnnoise's fixed frame size.
            "node.latency" = "480/48000";

            "filter.graph" = {
              "nodes" = [
                {
                  type = "ladspa";
                  name = "gate";
                  plugin = "${pkgs.lsp-plugins}/lib/ladspa/lsp-plugins-ladspa.so";
                  label = "http://lsp-plug.in/plugins/ladspa/gate_mono";
                  control = {
                    "Curve threshold (G)" = 0.12;
                    "Attack (ms)" = 5.0;
                    "Release (ms)" = 50.0;
                    "Reduction (G)" = 0.01;
                    "High-pass filter mode" = 1.0;
                    "Sidechain mode" = 1.0;
                    "Sidechain preamp (G)" = 2.0;
                  };
                }
                {
                  type = "ladspa";
                  name = "rnnoise";
                  plugin = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";
                  label = "noise_suppressor_mono";
                  control = {
                    "VAD Threshold (%)" = 75.0;
                    "VAD Grace Period (ms)" = 200.0;
                    "Retroactive VAD Grace (ms)" = 0.0;
                  };
                }
                {
                  type = "ladspa";
                  name = "compressor";
                  plugin = "${pkgs.lsp-plugins}/lib/ladspa/lsp-plugins-ladspa.so";
                  label = "http://lsp-plug.in/plugins/ladspa/compressor_mono";
                  control = {
                    "Sidechain mode" = 1.0;
                  };
                }
              ];
              "links" = [
                {
                  output = "gate:Output";
                  input = "rnnoise:Input";
                }
                {
                  output = "rnnoise:Output";
                  input = "compressor:Input";
                }
              ];
              "inputs" = [ "gate:Input" ];
              "outputs" = [ "compressor:Output" ];
            };

            "capture.props" = {
              "node.name" = "presonus_mic_capture";
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

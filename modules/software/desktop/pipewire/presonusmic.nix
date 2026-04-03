{ lib, config, pkgs, ... }:
#
# Native PipeWire processing chain for the PreSonus Studio 24c microphone.
# Replicates the active EasyEffects input chain:
#
#   [gate]       → LSP SC Gate Stereo (LADSPA)
#   [deepfilternet] → RNNoise (LADSPA, closest available native equivalent)
#   [compressor] → LSP SC Compressor Stereo (LADSPA)
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
            "media.name"       = "PreSonus Mic Processed";

            "filter.graph"."nodes" = [

              # Gate — non-SC version: only 2 audio in + 2 audio out.
              # SC version has extra sidechain audio ports that PipeWire wires
              # to the main signal, leaving the actual audio inputs as silence.
              {
                type   = "ladspa";
                name   = "gate";
                plugin = "${pkgs.lsp-plugins}/lib/ladspa/lsp-plugins-ladspa.so";
                label  = "http://lsp-plug.in/plugins/ladspa/gate_stereo";
                control = {
                  "Curve threshold (G)"   = 0.04467;  # -27 dB
                  "Attack (ms)"           = 5.0;
                  "Release (ms)"          = 100.0;
                  "Reduction (G)"         = 0.01;     # -40 dB when closed
                  "High-pass filter mode" = 1.0;
                  "Sidechain mode"        = 1.0;      # RMS detection
                  "Sidechain preamp (G)"  = 2.0;      # +6 dB
                };
              }

              # RNNoise noise suppression
              {
                type    = "ladspa";
                name    = "rnnoise";
                plugin  = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";
                label   = "noise_suppressor_stereo";
                control = {
                  "VAD Threshold (%)"          = 50.0;
                  "VAD Grace Period (ms)"      = 200.0;
                  "Retroactive VAD Grace (ms)" = 0.0;
                };
              }

              # Compressor — non-SC version: only 2 audio in + 2 audio out.
              {
                type   = "ladspa";
                name   = "compressor";
                plugin = "${pkgs.lsp-plugins}/lib/ladspa/lsp-plugins-ladspa.so";
                label  = "http://lsp-plug.in/plugins/ladspa/compressor_stereo";
                control = {
                  "Sidechain mode" = 1.0;  # RMS detection
                };
              }

            ]; # /filter.graph.nodes

            # ── Input: connects to the physical PreSonus mic ────────────
            # No target.object — WirePlumber auto-picks the highest-priority
            # source that isn't in the same link-group (i.e. the physical mic,
            # not the filter chain's own output). node.passive activates on demand.
            "capture.props" = {
              "node.name"      = "presonus_mic_capture";
              "audio.position" = [ "FL" "FR" ];
              "node.passive"   = true;
            };

            # ── Output: virtual mic source ────────────────────────────────
            "playback.props" = {
              "node.name"        = "mic_input";
              "node.description" = "Mic Input";
              "media.class"      = "Audio/Source";
              "audio.position"   = [ "FL" "FR" ];
              "priority.session" = 2200;
            };

          }; # /args
        }
      ]; # /context.modules

    }; # /services.pipewire
  };
}

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

              # ── Noise gate ──────────────────────────────────────────────
              # LSP SC Gate Stereo (LADSPA, absolute path — no discovery needed)
              # EasyEffects settings translated to linear gain (LSP LADSPA scale):
              #   curveThreshold = -27 dB  → "Curve threshold"       = 10^(-27/20) ≈ 0.04467
              #   reduction      = -40 dB  → "Reduction"             = 10^(-40/20) = 0.01
              #   attack         = 5 ms    → "Attack"                = 5.0
              #   release        = 100 ms  → "Release"               = 100.0
              #   hpfMode        = 1       → "High-pass filter mode"  = 1 (12 dB/oct)
              #   sidechainMode  = 1 (RMS) → "Sidechain mode"        = 1
              #   sidechainPreamp= +6 dB   → "Sidechain preamp"      = 10^(6/20) ≈ 2.0
              {
                type   = "ladspa";
                name   = "gate";
                plugin = "${pkgs.lsp-plugins}/lib/ladspa/lsp-plugins-ladspa.so";
                label  = "http://lsp-plug.in/plugins/ladspa/sc_gate_stereo";
                control = {
                  "Curve threshold (G)"   = 0.04467;
                  "Attack (ms)"           = 5.0;
                  "Release (ms)"          = 100.0;
                  "Reduction (G)"         = 0.01;
                  "High-pass filter mode" = 1.0;
                  "Sidechain mode"        = 1.0;
                  "Sidechain preamp (G)"  = 2.0;
                };
              }

              # ── Noise suppression ────────────────────────────────────────
              # RNNoise (LADSPA) — native replacement for DeepFilterNet.
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

              # ── Compressor ───────────────────────────────────────────────
              # LSP SC Compressor Stereo (LADSPA)
              # EasyEffects: sidechainMode = 1 (RMS), all else default.
              {
                type   = "ladspa";
                name   = "compressor";
                plugin = "${pkgs.lsp-plugins}/lib/ladspa/lsp-plugins-ladspa.so";
                label  = "http://lsp-plug.in/plugins/ladspa/sc_compressor_stereo";
                control = {
                  "Sidechain mode" = 1.0;   # RMS
                };
              }

            ]; # /filter.graph.nodes

            # ── Input: connects to the physical PreSonus mic ────────────
            # No target.object — WirePlumber auto-picks the highest-priority
            # source that isn't in the same link-group (i.e. the physical mic,
            # not the filter chain's own output). node.passive activates on demand.
            "capture.props" = {
              "node.name"    = "presonus_mic_capture";
              "node.passive" = true;
            };

            # ── Output: virtual mic source ────────────────────────────────
            "playback.props" = {
              "node.name"        = "mic_input";
              "node.description" = "Mic Input";
              "media.class"      = "Audio/Source/Virtual";
              "audio.position"   = [ "FL" "FR" ];
              "priority.session" = 2200;
            };

          }; # /args
        }
      ]; # /context.modules

    }; # /services.pipewire
  };
}

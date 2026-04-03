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
# When my.desktop.audio.mics.virtual is also enabled, the processed source
# (presonus_mic_processed) will be the highest-priority source, so the
# mic_input loopback auto-connects to it — apps see one clean default input.
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

            # ── Input: PreSonus Studio 24c physical device ──────────────
            "capture.props" = {
              "node.name"        = "presonus_mic_capture";
              "node.description" = "PreSonus Mic Capture";
              "audio.position"   = [ "FL" "FR" ];
              "target.object"    = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo";
              "stream.props"."node.passive" = true;
            };

            # ── Output: high-priority virtual source ──────────────────
            # priority.session = 2000 makes this the preferred default source
            # in WirePlumber, above physical USB mics (1025) and PCIe (1000).
            # The mic_input loopback from mics.nix will auto-connect here.
            "playback.props" = {
              "node.name"        = "presonus_mic_processed";
              "node.description" = "PreSonus Mic (Processed)";
              "media.class"      = "Audio/Source/Virtual";
              "audio.position"   = [ "FL" "FR" ];
              "priority.session" = 2000;
            };

          }; # /args
        }
      ]; # /context.modules

    }; # /services.pipewire
  };
}

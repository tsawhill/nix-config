{ lib, config, pkgs, ... }:
#
# Native PipeWire processing chain for the PreSonus Studio 24c microphone.
# Replicates the active EasyEffects input chain:
#
#   [deesser]  → skipped (default-only, no practical effect)
#   [stereo_tools mode=5]  → handled via audio.position (stereo → mono-ish)
#   [gate]     → LSP SC Gate Stereo (LV2)
#   [deepfilternet] → RNNoise (LADSPA, closest available native equivalent)
#   [speex]    → bypassed in EasyEffects, skipped
#   [reverb]   → bypassed in EasyEffects, skipped
#   [loudness] → TODO: add LSP Loudness plugin if desired
#   [compressor] → LSP SC Compressor Stereo (LV2)
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

    # LV2 plugin discovery — PipeWire's SPA LV2 plugin reads LV2_PATH from the
    # process environment. We expose it via /etc/environment.d/ so systemd's
    # user-session generator (systemd-environment-d-generator) injects it into
    # every user service (including pipewire.service) on login.
    environment.etc."environment.d/50-lv2-path.conf".text = ''
      LV2_PATH=${lib.makeSearchPathOutput "lib" "lib/lv2" [ pkgs.lsp-plugins ]}
    '';

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
              # LSP SC Gate Stereo (LV2)
              # EasyEffects gate settings (all linear-gain values per LSP LV2 spec):
              #   curveThreshold = -27 dB  → gt  = 10^(-27/20) ≈ 0.04467
              #   reduction      = -40 dB  → gr  = 10^(-40/20) = 0.01
              #   attack         = 5 ms    → at  = 5.0
              #   release        = 100 ms  → rt  = 100.0
              #   hpfMode        = 1       → shpm = 1  (12 dB/oct)
              #   sidechainMode  = 1 (RMS) → scm = 1
              #   sidechainPreamp= 6 dB   → scp = 10^(6/20) ≈ 2.0 (linear)
              {
                type   = "lv2";
                name   = "gate";
                plugin = "http://lsp-plug.in/plugins/lv2/sc_gate_stereo";
                control = {
                  "gt"   = 0.04467;   # Curve threshold (-27 dB, linear)
                  "at"   = 5.0;       # Attack (ms)
                  "rt"   = 100.0;     # Release (ms)
                  "gr"   = 0.01;      # Reduction (-40 dB, linear)
                  "shpm" = 1.0;       # High-pass filter mode: 12 dB/oct
                  "scm"  = 1.0;       # Sidechain mode: RMS
                  "scp"  = 2.0;       # Sidechain preamp (+6 dB, linear)
                };
              }

              # ── Noise suppression ────────────────────────────────────────
              # RNNoise (LADSPA) — native replacement for DeepFilterNet.
              # EasyEffects DeepFilterNet: postFilterBeta = 0.02
              # RNNoise does not expose a direct beta parameter; VAD threshold
              # is the closest tuning knob.
              {
                type    = "ladspa";
                name    = "rnnoise";
                plugin  = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";
                label   = "noise_suppressor_stereo";
                control = {
                  "VAD Threshold (%)"              = 50.0;
                  "VAD Grace Period (ms)"          = 200.0;
                  "Retroactive VAD Grace (ms)"     = 0.0;
                };
              }

              # ── Compressor ───────────────────────────────────────────────
              # LSP SC Compressor Stereo (LV2)
              # EasyEffects compressor: sidechainMode = 1 (RMS), all else default.
              {
                type   = "lv2";
                name   = "compressor";
                plugin = "http://lsp-plug.in/plugins/lv2/sc_compressor_stereo";
                control = {
                  "scm" = 1.0;   # Sidechain mode: RMS
                };
              }

            ]; # /filter.graph.nodes

            # ── Input: PreSonus Studio 24c physical device ──────────────
            "capture.props" = {
              "node.name"        = "presonus_mic_capture";
              "node.description" = "PreSonus Mic Capture";
              "audio.position"   = [ "FL" "FR" ];
              # Connect directly to the PreSonus physical device.
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

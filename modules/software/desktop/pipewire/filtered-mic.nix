{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.my.desktop.audio.filteredMic;
in
{
  options.my.desktop.audio.filteredMic = {
    enable = lib.mkEnableOption "native PipeWire microphone filtering";
    source = lib.mkOption {
      type = lib.types.str;
      description = "Physical PipeWire source node name to process.";
    };
    channel = lib.mkOption {
      type = lib.types.str;
      default = "MONO";
      description = "Physical input channel (for example MONO or AUX0).";
    };
    description = lib.mkOption {
      type = lib.types.str;
      default = "Filtered Mic";
      description = "Description of the microphone processing chain.";
    };
    controls = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.number);
      default = { };
      description = ''
        Per-stage control overrides for gate, hpf, rnnoise, eq_presence,
        eq_air, compressor, and limiter. Defaults preserve the tuned MOTU M2
        profile; gain controls marked (G) are linear amplitudes, not dB.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (
          name:
          builtins.elem name [
            "gate"
            "hpf"
            "rnnoise"
            "eq_presence"
            "eq_air"
            "compressor"
            "limiter"
          ]
        ) (builtins.attrNames cfg.controls);
        message = "filteredMic.controls contains an unknown filter stage.";
      }
    ];

    services.pipewire = {
      # Keep the selected capture device awake.
      wireplumber.extraConfig."13-filtered-mic-awake"."monitor.alsa.rules" = [
        {
          matches = [ { "node.name" = cfg.source; } ];
          actions.update-props."session.suspend-timeout-seconds" = 0;
        }
      ];

      extraLadspaPackages = with pkgs; [
        lsp-plugins
        rnnoise-plugin
      ];

      ##############################################################
      # Filter chain: physical mic → DSP → mic_input
      ##############################################################
      extraConfig.pipewire."95-filtered-mic"."context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = cfg.description;
            "media.name" = cfg.description;
            # RNNoise buffers its own 480-sample frames; it does not require
            # a 480-sample graph quantum. Both streams explicitly use 48 kHz.

            "filter.graph" = {
              "nodes" =
                map
                  (
                    node:
                    node
                    // {
                      control = node.control // (cfg.controls.${node.name} or { });
                    }
                  )
                  [
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
                        # Slow enough that a desk tap is over before the gate finishes
                        # opening. Speech is sustained and still opens it cleanly;
                        # a few-ms transient only ever gets it partway.
                        "Attack (ms)" = 15.0;
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
                        # Sidechain deaf below 700 Hz so fan/rumble can't hold the gate
                        # open and desk thumps can't trigger it — both are dominated by
                        # low frequencies, while speech keeps plenty of energy above.
                        "High-pass filter frequency (Hz)" = 700.0;
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
              "node.name" = "filtered_mic_capture";
              "target.object" = cfg.source;
              "audio.position" = [ cfg.channel ];
              "audio.rate" = 48000;
              "stream.dont-remix" = true;
              # No node.dont-fallback: this chain loads with the daemon, before
              # WirePlumber creates the ALSA nodes, and a target that is missing
              # at that moment errors the capture stream — which makes
              # module-filter-chain destroy mic_input for the rest of the session.
              "node.passive" = true;
            };

            "playback.props" = {
              "node.name" = "mic_input";
              "node.description" = "Mic Input";
              "media.class" = "Audio/Source";
              "audio.position" = [ "MONO" ];
              "audio.rate" = 48000;
              "priority.session" = 2200;
            };

          }; # /args
        }
      ]; # /context.modules

    }; # /services.pipewire
  };
}

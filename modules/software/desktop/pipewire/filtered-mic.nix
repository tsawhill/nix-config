{
  lib,
  config,
  pkgs,
  ...
}:
let
  mics = lib.filterAttrs (_: mic: mic.enable) config.my.desktop.audio.filteredMics;

  # Defaults were tuned on the MOTU M2; each mic's module overrides what differs.
  stages = [
    {
      type = "ladspa";
      name = "gate";
      plugin = "lsp-plugins-ladspa";
      label = "http://lsp-plug.in/plugins/ladspa/gate_mono";
      control = {
        # Absolute dBFS, so it is per mic and per gain setting (mic-measure).
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
        # Threshold and makeup suit the M2's level (mic-measure scales from it).
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

  stageNames = map (stage: stage.name) stages;

  micStages =
    mic:
    map (
      stage:
      stage
      // {
        control = stage.control // (mic.controls.${stage.name} or { });
      }
    ) stages;

  # Filter-chain args; filtered-mics.lua loads them when the source appears.
  mkChain = name: mic: {
    "node.description" = mic.description;
    "media.name" = mic.description;
    # RNNoise buffers its own 480-sample frames; it does not require
    # a 480-sample graph quantum. Both streams explicitly use 48 kHz.
    "filter.graph" = {
      nodes = micStages mic;
      links = [
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
      inputs = [ "gate:Input" ];
      outputs = [ "limiter:Output" ];
    };
    "capture.props" = {
      "node.name" = "filtered_mic_capture.${name}";
      "target.object" = mic.source;
      "audio.position" = [ mic.channel ];
      "audio.rate" = 48000;
      "stream.dont-remix" = true;
      "node.passive" = true;
      # Never process another mic; wait unlinked until torn down on unplug.
      "node.dont-fallback" = true;
      "node.linger" = true;
    };
    "playback.props" = {
      "node.name" = "mic_input";
      "node.description" = "Mic Input";
      "media.class" = "Audio/Source";
      "audio.position" = [ "MONO" ];
      "audio.rate" = 48000;
      "priority.session" = 2200;
    };
  };

  # Gate and compressor settings mic-measure reads, from merged stage controls.
  levelControls =
    nodes:
    let
      control = lib.listToAttrs (map (node: lib.nameValuePair node.name node.control) nodes);
    in
    {
      inherit (control) gate compressor;
    };

  micMeasure = pkgs.writeShellApplication {
    name = "mic-measure";
    runtimeInputs = [
      config.services.pipewire.package
      pkgs.coreutils
      pkgs.ffmpeg-headless
      pkgs.gawk
      pkgs.jq
    ];
    text = ''
      MIC_PROFILES=${
        lib.escapeShellArg (
          builtins.toJSON (
            lib.mapAttrs' (
              name: mic:
              lib.nameValuePair mic.source (
                {
                  inherit name;
                  inherit (mic) channel description;
                }
                // levelControls (micStages mic)
              )
            ) config.my.desktop.audio.filteredMics
          )
        )
      }
      MIC_DEFAULTS=${lib.escapeShellArg (builtins.toJSON (levelControls stages))}
      # The M2's normal-speech peak (dBFS) when the default compressor was tuned.
      MIC_REFERENCE_PEAK=-16
    ''
    + builtins.readFile ./mic-measure.sh;
  };
in
{
  options.my.desktop.audio.filteredMics = lib.mkOption {
    default = { };
    description = ''
      Microphones to process, keyed by name. A mic's chain provides mic_input
      only while it's plugged in. mic-measure generates entries for new mics.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Process this mic on this host.";
            };
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
              default = "${name} (Processed)";
              description = "Description of the processed source.";
            };
            controls = lib.mkOption {
              type = lib.types.attrsOf (lib.types.attrsOf lib.types.number);
              default = { };
              description = ''
                Per-stage control overrides for gate, hpf, rnnoise, eq_presence,
                eq_air, compressor, and limiter. Gain controls marked (G) are
                linear amplitudes, not dB.
              '';
            };
          };
        }
      )
    );
  };

  config = lib.mkMerge [
    # Available even before any mic is configured, to measure new ones.
    { environment.systemPackages = [ micMeasure ]; }

    (lib.mkIf (mics != { }) {
      assertions = lib.mapAttrsToList (name: mic: {
        assertion = lib.all (stage: builtins.elem stage stageNames) (builtins.attrNames mic.controls);
        message = "filteredMics.${name}.controls contains an unknown filter stage.";
      }) mics;

      # Chains run inside WirePlumber, so it needs the plugins. No daemon-side
      # loopback here: one crashed pipewire on the cube.
      services.pipewire.wireplumber = {
        extraLadspaPackages = with pkgs; [
          lsp-plugins
          rnnoise-plugin
        ];
        extraScripts."filtered-mics.lua" = builtins.readFile ./filtered-mics.lua;
        extraConfig."95-filtered-mics" = {
          "wireplumber.components" = [
            {
              name = "filtered-mics.lua";
              type = "script/lua";
              provides = "custom.filtered-mics";
            }
          ];
          "wireplumber.profiles".main."custom.filtered-mics" = "required";
          "filtered-mics.rules" = lib.mapAttrsToList (name: mic: {
            matches = [ { "node.name" = mic.source; } ];
            actions.load-filter-chain = mkChain name mic;
          }) mics;
          # Keep processed capture devices awake.
          "monitor.alsa.rules" = [
            {
              matches = map (mic: { "node.name" = mic.source; }) (lib.attrValues mics);
              actions.update-props."session.suspend-timeout-seconds" = 0;
            }
          ];
        };
      };
    })
  ];
}

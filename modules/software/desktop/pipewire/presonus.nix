{ lib, config, pkgs, ... }:
let
  cfg = config.my.audio.presonus;
in
{
  options.my.audio.presonus = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable PreSonus mic with effects chain (gate, noise removal, deesser, etc.)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      calf
      zam-plugins
    ];

    services.pipewire = {
      extraConfig.pipewire."94-presonus-effects" = {
        "context.modules" = [
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.name" = "PreSonus_Effects";
              "node.description" = "PreSonus with Effects";
              "media.class" = "Audio/Source";
              "audio.position" = [ "FL" "FR" ];
              "capture.props" = {
                "node.name" = "PreSonus_Effects_in";
                "node.target.object" = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo";
              };
              "playback.props" = {
                "node.name" = "PreSonus_Effects_out";
              };
              "filter.graph" = {
                "nodes" = [
                  {
                    "type" = "builtin";
                    "name" = "input";
                    "label" = "input";
                  }
                  {
                    "type" = "lv2";
                    "name" = "deesser";
                    "plugin" = "urn:zamaudio:ZamDeesser";
                  }
                  {
                    "type" = "lv2";
                    "name" = "gate";
                    "plugin" = "urn:calf:gate";
                  }
                  {
                    "type" = "lv2";
                    "name" = "compressor";
                    "plugin" = "urn:calf:compressor";
                  }
                  {
                    "type" = "builtin";
                    "name" = "output";
                    "label" = "output";
                  }
                ];
                "links" = [
                  { "output" = "input:Out"; "input" = "deesser:in"; }
                  { "output" = "deesser:out"; "input" = "gate:in"; }
                  { "output" = "gate:out"; "input" = "compressor:in"; }
                  { "output" = "compressor:out"; "input" = "output:In"; }
                ];
              };
            };
          }
        ];
      };

      wireplumber.extraConfig."95-presonus-routing"."stream.rules" = [
        {
          matches = [{ "node.name" = "PreSonus_Effects_out"; }];
          actions.update-props."target.object" = "mic_input";
        }
      ];
    };
  };
}

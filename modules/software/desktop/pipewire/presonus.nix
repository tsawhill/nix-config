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
      extraConfig.pipewire."94-presonus-filter" = {
        "context.modules" = [
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.name" = "PreSonus_to_Mic";
              "node.description" = "PreSonus → Mic Input";
              "media.class" = "Audio/Source";
              "audio.position" = [ "FL" "FR" ];
              "filter.graph" = {
                "nodes" = [
                  {
                    "type" = "builtin";
                    "name" = "in_node";
                    "label" = "input";
                    "control" = { "port.name" = "input"; };
                  }
                  {
                    "type" = "builtin";
                    "name" = "out_node";
                    "label" = "output";
                    "control" = { "port.name" = "output"; };
                  }
                ];
                "links" = [
                  { "output" = "in_node:In"; "input" = "out_node:In"; }
                ];
              };
              "capture.props" = {
                "node.name" = "PreSonus_to_Mic_input";
                "node.target.object" = "alsa_input.usb-PreSonus_Studio_24c_SC1E21081241-00.analog-stereo";
              };
              "playback.props" = {
                "node.name" = "PreSonus_to_Mic_output";
                "target.object" = "mic_input";
              };
            };
          }
        ];
      };
    };
  };
}

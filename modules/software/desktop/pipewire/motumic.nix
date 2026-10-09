{ lib, config, ... }:
{
  options.my.desktop.audio.motuMic.enable =
    lib.mkEnableOption "MOTU M2 microphone preset for the shared filter chain";

  config = lib.mkIf config.my.desktop.audio.motuMic.enable {
    my.desktop.audio.filteredMic = {
      enable = true;
      source = lib.mkDefault "alsa_input.usb-MOTU_M2_M2MA072BWT-00.pro-input-0";
      channel = lib.mkDefault "AUX0";
      description = lib.mkDefault "MOTU M2 Mic (Processed)";
    };

    # Preserve the MOTU preset's output-device wake behavior too.
    services.pipewire.wireplumber.extraConfig."13-motu-awake"."monitor.alsa.rules" = [
      {
        matches = [ { "node.name" = "~alsa_output[.]usb-MOTU_M2_.*"; } ];
        actions.update-props."session.suspend-timeout-seconds" = 0;
      }
    ];
  };
}

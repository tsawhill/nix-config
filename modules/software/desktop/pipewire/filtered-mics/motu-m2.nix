{
  my.desktop.audio.filteredMics.motu-m2 = {
    source = "alsa_input.usb-MOTU_M2_M2MA072BWT-00.pro-input-0";
    channel = "AUX0";
    description = "MOTU M2 Mic (Processed)";
    # Fan peaks -46 dBFS, speech -16 at the current gain knob; moving it means rerunning mic-measure.
    controls.gate."Curve threshold (G)" = 0.0126; # -38 dBFS
  };
}

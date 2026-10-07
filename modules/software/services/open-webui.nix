{
  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
    # Setting this replaces the module's defaults, so the telemetry opt-outs are repeated.
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
      # UI chats get built-in tools; qwen2.5-coder prints tool calls as text instead of answering.
      DEFAULT_MODELS = "qwen3:8b";
    };
  };
}

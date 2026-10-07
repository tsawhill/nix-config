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
      # qwen2.5-coder is for deployctl and makes a poor chat model.
      DEFAULT_MODELS = "huihui_ai/qwen3-abliterated:8b";
      # Built-in tool schemas swamp 8B models; they answer every message as a tool-routing task.
      DEFAULT_MODEL_METADATA = builtins.toJSON { capabilities.builtin_tools = false; };
    };
  };
}

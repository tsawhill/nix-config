{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "0.0.0.0";
    openFirewall = true;
    # Pulled by ollama-model-loader.service, so a wiped model store heals on
    # the next deploy. qwen2.5-coder:7b is ~4.7 GiB at Q4_K_M, which leaves the
    # 2070 Super's 8 GiB enough room for deployctl's 16k context window.
    loadModels = [ "qwen2.5-coder:7b" ];
  };
}

{ self, ... }:
{
  imports = [
    ./base
    ../hardware/nvidia.nix # Import NVIDIA driver configuration for CUDA
    "${self}/modules/software/services/ollama-cuda.nix" # Import Ollama-CUDA service configuration
    "${self}/modules/software/services/open-webui.nix" # Import open-webui service configuration
  ];
  networking.hostName = "llm-nix";
}

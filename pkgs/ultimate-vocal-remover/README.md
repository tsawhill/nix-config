# Ultimate Vocal Remover (CPU)

Installed by the media-creation bundle as `ultimate-vocal-remover`. It can also
be run without a switch via `nix run .#ultimate-vocal-remover`. The first launch
downloads Python dependencies from PyPI and the PyTorch CPU wheel index. UVR's
model download menu supplies the separation models separately. Internet access
and disk space for the Python environment and models are required.

The source archive is pinned and hashed. Python dependencies are installed at
runtime with compatibility constraints, not a complete reproducible lockfile.
This package is CPU-only; it does not configure CUDA or ROCm.

Data lives under `$XDG_DATA_HOME/ultimate-vocal-remover`, defaulting to
`~/.local/share/ultimate-vocal-remover`. Each launcher version gets its own app
and Python environment; model downloads are shared. Avoid the upstream app
self-updater: source updates should be made in the Nix package.

For an import check without opening the GUI:

```sh
ultimate-vocal-remover --check
```

For the Dynamo sound replacement, select your audio in UVR, download/select a
vocal-separation model, disable GPU conversion, and export the vocals as WAV.
Audition the result before using it as the replacement in Deadlock Forge.
Audacity (also in the media-creation bundle) can trim silence and adjust volume.

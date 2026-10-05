#!/usr/bin/env bash
set -euo pipefail

# UVR uses pyglet only to register fonts; Tk does not need an OpenGL context.
export PYGLET_SHADOW_WINDOW=false

: "${UVR_SOURCE:?}" "${UVR_ENV_VERSION:?}" "${UVR_CONSTRAINTS:?}"
uvr_root="${XDG_DATA_HOME:-$HOME/.local/share}/ultimate-vocal-remover"
uvr_app="$uvr_root/$UVR_ENV_VERSION"
mkdir -p "$uvr_app"
exec 9>"$uvr_root/setup.lock"
flock 9

if [[ ! -e "$uvr_app/.source-ready" ]]; then
    cp -R "$UVR_SOURCE/." "$uvr_app/"
    chmod -R u+w "$uvr_app"
    touch "$uvr_app/.source-ready"
fi

# All revisions share model downloads; settings remain local to each revision.
mkdir -p "$uvr_root/models"
if [[ ! -L "$uvr_app/models" ]]; then
    cp -Rn "$uvr_app/models/." "$uvr_root/models/"
    rm -rf -- "$uvr_app/models"
    ln -s "$uvr_root/models" "$uvr_app/models"
fi

if [[ ! -e "$uvr_app/.dependencies-ready" ]]; then
    echo "Setting up UVR's CPU dependencies (first launch requires internet)..."
    uv venv --allow-existing --python /usr/bin/python3.11 --system-site-packages "$uvr_app/venv"
    uv pip install --python "$uvr_app/venv/bin/python" \
        --index-url https://download.pytorch.org/whl/cpu \
        'torch==2.5.1+cpu' 'torchaudio==2.5.1+cpu' 'torchvision==0.20.1+cpu'
    uv pip install --python "$uvr_app/venv/bin/python" \
        --constraint "$UVR_CONSTRAINTS" --requirement "$uvr_app/requirements.txt"
    touch "$uvr_app/.dependencies-ready"
fi
flock -u 9
exec 9>&-

cd "$uvr_app"
if [[ "${1:-}" == "--check" ]]; then
    exec venv/bin/python -c 'import tkinter, torch, onnxruntime, librosa, soundfile, separate; print("UVR imports OK; Torch", torch.__version__, "ONNX providers:", onnxruntime.get_available_providers())'
fi
exec venv/bin/python UVR.py "$@"

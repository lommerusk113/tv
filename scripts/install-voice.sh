#!/usr/bin/env bash
# Host: voice control dependencies, all in the user's home: whisper.cpp from Homebrew (whisper-cli) and the
# multilingual "base" model (148 MB, English + Norwegian) in ~/.local/share/tv-project/whisper/.
# Usage: scripts/install-voice.sh            install
#        scripts/install-voice.sh --remove   uninstall whisper-cpp and delete the model
set -euo pipefail
dir=${XDG_DATA_HOME:-$HOME/.local/share}/tv-project/whisper
model=$dir/ggml-base.bin
sha1=465707469ff3a37a2b9b8d8f89f2f99de7299dac

if [ "${1:-}" = --remove ]; then
    brew uninstall whisper-cpp || true
    rm -rf "$dir"
    echo "removed"
    exit 0
fi

command -v whisper-cli >/dev/null || HOMEBREW_NO_AUTO_UPDATE=1 brew install whisper-cpp
if ! echo "$sha1  $model" | sha1sum -c --status 2>/dev/null; then
    mkdir -p "$dir"
    curl -fL --retry 3 -o "$model.tmp" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
    echo "$sha1  $model.tmp" | sha1sum -c --status
    mv "$model.tmp" "$model"
fi
echo "installed: $(command -v whisper-cli), $model"

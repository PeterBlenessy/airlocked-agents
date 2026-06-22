#!/usr/bin/env bash
# mac/download-model.sh — fetch the local GGUF model deterministically.
# Idempotent: skips download if the file already exists. Reads vars from .env.
set -euo pipefail

# Load .env from repo root.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.env" ] && set -a && . "$ROOT/.env" && set +a

: "${MODEL_REPO:?set MODEL_REPO in .env}"
: "${MODEL_FILE:?set MODEL_FILE in .env}"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"
mkdir -p "$MODEL_DIR"

TARGET="$MODEL_DIR/$MODEL_FILE"
if [ -f "$TARGET" ]; then
  echo "Model already present: $TARGET — skipping."
  exit 0
fi

echo "Downloading $MODEL_FILE from $MODEL_REPO into $MODEL_DIR ..."
# huggingface-cli is installed via the Brewfile.
huggingface-cli download "$MODEL_REPO" "$MODEL_FILE" \
  --local-dir "$MODEL_DIR" --local-dir-use-symlinks False

echo "Done: $TARGET"
echo "Re-run 'make mac' so launchd picks up the model path."

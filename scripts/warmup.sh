#!/usr/bin/env bash
set -euo pipefail
source ./.env 2>/dev/null || true
MODEL="${1:-${DEFAULT_MODEL:-llama3.1:8b-instruct-q4}}"
HOST="${OLLAMA_BASE_URL:-http://localhost:11434}"

if ! docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
  echo "[warmup] Ollama container not running." >&2
  exit 1
fi

echo "[warmup] warming model: $MODEL"
curl -s "$HOST/api/generate" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"prompt\":\"hi\",\"stream\":false,\"options\":{\"num_predict\":16}}" >/dev/null
echo "[warmup] done."

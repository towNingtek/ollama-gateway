#!/usr/bin/env bash
set -euo pipefail
source ./.env 2>/dev/null || true
MODEL="${1:-${DEFAULT_MODEL:-llama3.1:8b-instruct-q4}}"
HOST="${OLLAMA_BASE_URL:-http://localhost:11434}"

if ! docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
  echo "[pull-model] Ollama container not running. Start it with: docker compose up -d" >&2
  exit 1
fi

echo "[pull-model] pulling model: $MODEL"
docker exec -e OLLAMA_HOST="$HOST" -i ollama ollama pull "$MODEL"

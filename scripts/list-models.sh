#!/usr/bin/env bash
set -euo pipefail
if ! docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
  echo "[list-models] Ollama container not running." >&2
  exit 1
fi
docker exec -i ollama ollama list

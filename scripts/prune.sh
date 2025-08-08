#!/usr/bin/env bash
set -euo pipefail
if ! docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
  echo "[prune] Ollama container not running." >&2
  exit 1
fi
echo "[prune] removing unused model blobs (safe)."
docker exec -i ollama ollama prune

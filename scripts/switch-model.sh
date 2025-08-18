#!/usr/bin/env bash
set -euo pipefail
MODEL="${1:-}"
[ -z "$MODEL" ] && { echo "Usage: $0 <model_tag> (e.g., llama3:instruct)"; exit 1; }
sed -i "s|^DEFAULT_MODEL=.*|DEFAULT_MODEL=$MODEL|" .env
echo "[switch] DEFAULT_MODEL -> $MODEL"
docker compose up -d --force-recreate models_init
docker compose logs -f --since=1m models_init

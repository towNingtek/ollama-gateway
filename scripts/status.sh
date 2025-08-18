#!/usr/bin/env bash
set -euo pipefail
HOST="${OLLAMA_BASE_URL:-http://localhost:11434}"
echo "== /api/tags =="
curl -fsS "$HOST/api/tags" || { echo "[ERR] ollama not ready"; exit 1; }
echo -e "\n== quick generate =="
curl -fsS "$HOST/api/generate" \
  -H 'Content-Type: application/json' \
  -d '{"model":"'"${DEFAULT_MODEL:-llama3:instruct}"'","prompt":"你好，打一行自我介紹","stream":false}' \
  | sed 's/.*"response":"\([^"]*\)".*/\1/' || true
echo

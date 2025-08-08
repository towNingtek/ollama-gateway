#!/usr/bin/env bash
set -euo pipefail
BASE="${GATEWAY:-http://localhost:8082}"
MODEL="${OPENAI_MODEL:-openai/gpt-4o-mini}"
SYS="${SYS:-請以繁體中文（台灣用語）回答。}"
PROMPT="${*:-用一句話介紹你自己}"

BODY="$(jq -c -n --arg m "$MODEL" --arg s "$SYS" --arg p "$PROMPT" \
  '{model:$m, messages:[{role:"system",content:$s},{role:"user",content:$p}], stream:false}')"

RESP="$(curl -sS --http1.1 "$BASE/api/chat" \
  -H 'Content-Type: application/json' -d "$BODY")"

# 優先取 OpenAI 原生欄位；退回統一格式；最後印原文以便除錯
OUT="$(printf '%s' "$RESP" | jq -r '(.choices[0].message.content // .message.content // empty)')"
if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
else
  printf '%s\n' "$RESP"
fi

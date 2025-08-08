#!/usr/bin/env bash
set -euo pipefail
BASE="${GATEWAY:-http://localhost:8082}"
MODEL="${MODEL:-llama3:instruct}"
SYS="${SYS:-請以繁體中文（台灣用語）回答。}"
PROMPT="${*:-用一句話介紹你自己}"
if ! command -v jq >/dev/null; then echo "[ERR] jq not found"; exit 1; fi

build_body() {
  if [ -n "${OPTIONS_JSON:-}" ]; then
    echo "${OPTIONS_JSON}" | jq -e . >/dev/null 2>&1 || { echo "[ERR] OPTIONS_JSON 不是合法 JSON"; exit 1; }
    jq -c -n --arg m "$MODEL" --arg s "$SYS" --arg p "$PROMPT" --argjson opt "${OPTIONS_JSON}" \
      '{model:$m, messages:[{role:"system",content:$s},{role:"user",content:$p}], stream:false, options:$opt}'
  else
    jq -c -n --arg m "$MODEL" --arg s "$SYS" --arg p "$PROMPT" \
      '{model:$m, messages:[{role:"system",content:$s},{role:"user",content:$p}], stream:false}'
  fi
}
BODY="$(build_body)"

tmpdir="$(mktemp -d)"; hdr="$tmpdir/h"; out="$tmpdir/b"
set +e
curl -q -sS --http1.1 -D "$hdr" -o "$out" "$BASE/api/chat" \
  -H 'Content-Type: application/json' -d "$BODY"
# 兼容 HTTP/1.x 與 HTTP/2
code=$(awk 'toupper($1) ~ /^HTTP\/[0-9.]+$/ {c=$2} END{ if (c=="") print 0; else print c }' "$hdr")
ctype=$(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {print $0}' "$hdr" | head -n1 | tr -d "\r")
set -e

if [ -z "${code:-}" ] || [ "$code" -lt 200 ] || [ "$code" -ge 300 ]; then
  echo "[ERR] HTTP ${code:-0} from $BASE/api/chat" >&2
  [ -n "$ctype" ] && echo "$ctype" >&2
  echo "--- response body (first 400 chars) ---" >&2
  head -c 400 "$out" >&2 || true
  echo >&2
  rm -rf "$tmpdir"; exit 1
fi

if [ ! -s "$out" ]; then
  echo "[ERR] empty body from $BASE/api/chat" >&2
  rm -rf "$tmpdir"; exit 1
fi

if ! echo "$ctype" | grep -qi 'application/json'; then
  echo "[ERR] non-JSON response ($ctype). raw body below:" >&2
  cat "$out"
  echo >&2
  rm -rf "$tmpdir"; exit 1
fi

jq -r '.message.content' < "$out"
rm -rf "$tmpdir"

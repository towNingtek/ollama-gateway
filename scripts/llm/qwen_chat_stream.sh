#!/usr/bin/env bash
set -euo pipefail
BASE="${GATEWAY:-http://localhost:8082}"
MODEL="${MODEL:-qwen2.5:7b-instruct}"
SYS="${SYS:-請以繁體中文（台灣用語）回答。}"
PROMPT="${*:-給我三個客服問候語}"
RAWLOG="${RAWLOG:-/tmp/llama_stream_raw.ndjson}"

build_body() {
  if [ -n "${OPTIONS_JSON:-}" ]; then
    echo "${OPTIONS_JSON}" | jq -e . >/dev/null 2>&1 || { echo "[ERR] OPTIONS_JSON 不是合法 JSON"; exit 1; }
    jq -c -n --arg m "$MODEL" --arg s "$SYS" --arg p "$PROMPT" --argjson opt "${OPTIONS_JSON}" \
      '{model:$m, messages:[{role:"system",content:$s},{role:"user",content:$p}], stream:true, options:$opt}'
  else
    jq -c -n --arg m "$MODEL" --arg s "$SYS" --arg p "$PROMPT" \
      '{model:$m, messages:[{role:"system",content:$s},{role:"user",content:$p}], stream:true}'
  fi
}
BODY="$(build_body)"

# 健康檢查
curl -sS --http1.1 -I "$BASE/" >/dev/null || { echo "[ERR] cannot reach $BASE" >&2; exit 1; }

# 準備 Python 腳本到暫存檔，stdin 留給管線
PYFILE="$(mktemp)"
cat > "$PYFILE" <<'PY'
import sys, json
raw_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/llama_stream_raw.ndjson"
log = open(raw_path, "w", buffering=1, encoding="utf-8")
emitted = False
buf = ""
def flush_lines():
    global buf, emitted
    while True:
        i = buf.find("\n")
        if i < 0:
            return
        line = buf[:i]; buf = buf[i+1:]
        log.write(line + "\n")
        ls = line.strip()
        if not ls.startswith("{"):
            continue
        try:
            obj = json.loads(ls)
        except Exception:
            continue
        msg = (obj.get("message") or {})
        content = msg.get("content")
        if content:
            sys.stdout.write(content)
            sys.stdout.flush()
            emitted = True

for chunk in sys.stdin.buffer:
    try:
        s = chunk.decode("utf-8", "ignore")
    except Exception:
        continue
    buf += s
    flush_lines()

if buf:
    log.write(buf)
    try:
        obj = json.loads(buf.strip())
        msg = (obj.get("message") or {})
        content = msg.get("content")
        if content:
            sys.stdout.write(content)
            sys.stdout.flush()
            emitted = True
    except Exception:
        pass

if not emitted:
    print("\n[ERR] no JSON lines parsed; check {}".format(raw_path), file=sys.stderr)
print()
PY

# 取流 → stdin 餵給 Python；忽略 curl 的退出碼（避免 (23) 噪音）
set +e
curl -sS --http1.1 --no-buffer "$BASE/api/chat" \
  -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null \
| python3 -u "$PYFILE" "$RAWLOG"
ret=$?
rm -f "$PYFILE"
set -e
exit 0

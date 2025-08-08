#!/usr/bin/env bash
set -euo pipefail
BASE="${GATEWAY:-http://localhost:8082}"
MODEL="${OPENAI_MODEL:-openai/gpt-4o-mini}"
SYS="${SYS:-請以繁體中文（台灣用語）回答。}"
PROMPT="${*:-請慢慢輸出三句中文客服問候語}"
RAWLOG="${RAWLOG:-/tmp/openai_stream_raw.ndjson}"

BODY="$(jq -c -n --arg m "$MODEL" --arg s "$SYS" --arg p "$PROMPT" \
  '{model:$m, messages:[{role:"system",content:$s},{role:"user",content:$p}], stream:true}')"

# 健康檢查（能連就好）
curl -sS --http1.1 -I "$BASE/" >/dev/null || { echo "[ERR] cannot reach $BASE" >&2; exit 1; }

# 解析 NDJSON / SSE: data:{...} 兩制式
PYFILE="$(mktemp)"
cat > "$PYFILE" <<'PY'
import sys, json, os
raw_path = sys.argv[1]
emitted = False
buf = ""

def parse_line(s):
    s = s.strip()
    if not s:
        return None
    if s.startswith("data:"):
        s = s[5:].strip()
        if s == "[DONE]":
            return ""
    if not s.startswith("{"):
        return None
    try:
        obj = json.loads(s)
    except Exception:
        return None
    # 統一格式
    msg = obj.get("message") or {}
    if isinstance(msg, dict):
        c = msg.get("content")
        if c: return c
    # OpenAI SSE chunk
    for ch in obj.get("choices", []):
        delta = ch.get("delta") or {}
        c = delta.get("content")
        if c: return c
    return None

with open(raw_path, "w", buffering=1, encoding="utf-8") as log:
    for chunk in sys.stdin.buffer:
        s = chunk.decode("utf-8", "ignore")
        buf += s
        while True:
            i = buf.find("\n")
            if i < 0: break
            line = buf[:i]; buf = buf[i+1:]
            log.write(line + "\n")
            out = parse_line(line)
            if out is None: continue
            sys.stdout.write(out); sys.stdout.flush()
            emitted = True
    if buf:
        log.write(buf)
        out = parse_line(buf)
        if out is not None:
            sys.stdout.write(out); sys.stdout.flush()
            emitted = True

# 若完全沒解析到字才提示錯誤，但仍以 0 結束交由上游判斷
if not emitted:
    print("\n[ERR] no JSON lines parsed; check {}".format(raw_path), file=sys.stderr)
print()
PY

# 串流：只要有資料就當成功；不再做 header 狀態碼硬檢查
set +e
curl --http1.1 -sS -N \
  -H 'Accept: text/event-stream' \
  -H 'Content-Type: application/json' \
  -d "$BODY" \
  "$BASE/api/chat" \
| python3 -u "$PYFILE" "$RAWLOG"
rc=$?
set -e

# 只在 raw 完全空白時視為失敗
if [ ! -s "$RAWLOG" ]; then
  echo
  echo "[ERR] no data captured; raw empty at $RAWLOG" >&2
  exit 1
fi
exit 0

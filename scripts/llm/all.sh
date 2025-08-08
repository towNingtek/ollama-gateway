#!/usr/bin/env bash
# Run all LLM smoke tests and save outputs.
set -euo pipefail

PROMPT="${*:-給我三個客服問候語}"
OUTDIR="scripts/llm/out"
mkdir -p "$OUTDIR"

ts="$(date +%Y%m%d-%H%M%S)"

have() { command -v "$1" >/dev/null 2>&1; }

ensure_script() {
  local p="$1"
  if [ ! -x "$p" ]; then
    echo "[SKIP] $p 不存在或不可執行（跳過）"
    return 1
  fi
  return 0
}

run() {
  local title="$1"; shift
  local file="$OUTDIR/${ts}_${title}.txt"

  echo "=== $title ==="
  local start end dur code

  # 確保不因單一項目出錯而中斷整批
  set +e
  start=$(date +%s)

  # 把 stdout+stderr 同步印出 & 存檔
  "$@" 2>&1 | tee "$file"
  code=${PIPESTATUS[0]}

  end=$(date +%s)
  set -e
  dur=$(( end - start ))

  if [ $code -ne 0 ]; then
    echo "[ERR] $title exited $code（詳見 $file）" | tee -a "$file"
  fi
  echo "[done $title in ${dur}s]"
  echo
}

# 允許用環境變數覆蓋（例如 OPTIONS_JSON、SYS、MODEL、GATEWAY）
export PROMPT

# 檢查腳本存在性（不存在就跳過）
declare -A CMDS=(
  ["llama_nonstream"]="scripts/llm/llama_chat.sh"
  ["llama_stream"]="scripts/llm/llama_chat_stream.sh"
  ["openai_nonstream"]="scripts/llm/openai_chat.sh"
  ["openai_stream"]="scripts/llm/openai_chat_stream.sh"
)

for key in "${!CMDS[@]}"; do
  ensure_script "${CMDS[$key]}" || unset "CMDS[$key]"
done

# 逐一跑（有就跑）
[ -n "${CMDS[llama_nonstream]+x}" ]  && run "llama_nonstream"  "${CMDS[llama_nonstream]}"  "$PROMPT"
[ -n "${CMDS[llama_stream]+x}" ]     && run "llama_stream"     "${CMDS[llama_stream]}"     "$PROMPT"
[ -n "${CMDS[openai_nonstream]+x}" ] && run "openai_nonstream" "${CMDS[openai_nonstream]}" "$PROMPT"
[ -n "${CMDS[openai_stream]+x}" ]    && run "openai_stream"    "${CMDS[openai_stream]}"    "$PROMPT"

echo "📄 Saved to ${OUTDIR}/${ts}_*.txt"


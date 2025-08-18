# scripts/

這裡收錄各種 **LLM 測試腳本**。最常用的是 `llm/` 底下的四支，以及整合的 `all.sh`。

## 目錄
````

scripts/
└── llm/
├── all.sh                      # 一次跑四種（Llama/OpenAI × non-stream/stream）
├── llama\_chat.sh               # Llama 非串流
├── llama\_chat\_stream.sh        # Llama 串流（NDJSON）
├── openai\_chat.sh              # OpenAI 非串流
└── openai\_chat\_stream.sh       # OpenAI 串流（NDJSON；已處理 SSE → NDJSON）

````

## 共同環境變數
- `GATEWAY`：Gateway 位址（預設 `http://localhost:8082`）
- `SYS`：系統提示（預設 `請以繁體中文（台灣用語）回答。`）
- `OPTIONS_JSON`（僅 Llama）：Ollama options（如：`{"num_predict":64,"num_thread":8}`）

### Llama 專用
- `MODEL`（預設 `llama3:instruct`）

### OpenAI 專用
- `OPENAI_MODEL`（預設 `openai/gpt-4o-mini`）
- `OPENAI_API_KEY` 需在 Gateway 那層設定（`.env` 或部署環境）

---

## 用法

### 一次全跑
```bash
scripts/llm/all.sh "給我三個客服問候語"
````

會輸出四段結果，並儲存到 `scripts/llm/out/<timestamp>_*.txt`。

### Llama：非串流

```bash
scripts/llm/llama_chat.sh "用一句話介紹你自己"
```

### Llama：串流（NDJSON）

```bash
scripts/llm/llama_chat_stream.sh "給我三個客服問候語"
```

### OpenAI：非串流

```bash
scripts/llm/openai_chat.sh "用一句話介紹你自己"
```

### OpenAI：串流（NDJSON）

```bash
scripts/llm/openai_chat_stream.sh "請慢慢輸出三句中文客服問候語"
```

---

## 參數技巧

### 指定（或限縮）Llama 的 options

```bash
OPTIONS_JSON='{"num_predict":64,"num_thread":8}' \
  scripts/llm/llama_chat.sh "請用 64 token 內回答"
```

### 切換模型

```bash
MODEL='llama3:instruct' scripts/llm/llama_chat.sh "你好"
OPENAI_MODEL='openai/gpt-4o-mini' scripts/llm/openai_chat.sh "你好"
```

### 切換 Gateway 位址

```bash
GATEWAY='http://127.0.0.1:8082' scripts/llm/all.sh "Hello"
```

---

## 串流輸出格式（NDJSON）

所有串流腳本都以 **NDJSON** 形式回來（每行一個 JSON），範例行：

```json
{"model":"llama3:instruct","message":{"role":"assistant","content":"您"},"done":false}
```

當 `done: true` 時表示完成。

---

## 常見問題

* `curl (18) transfer closed ...`
  多為連線收尾時機差；目前腳本已容忍，只要過程有資料就算成功。
* 完全沒輸出？
  先看 Gateway 日誌：

  ```bash
  docker compose logs -f gateway
  ```

  再檢查環境變數（特別是 `OPENAI_API_KEY`、`OLLAMA_BASE_URL`）。

---

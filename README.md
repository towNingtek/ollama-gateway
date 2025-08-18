# ollama-gateway

一個簡潔的 **LLM API Gateway**，用同一個 `/api/chat` 端點，同時打到：
- 本機 **Ollama**（如：`llama3:instruct`）
- 雲端 **OpenAI**（如：`openai/gpt-4o-mini`）

並且支援 **非串流**與**串流（NDJSON）** 輸出，方便前端或 CLI 測試。

## ✨ Features
- 單一 API 介面切換模型：`model: "llama3:instruct"` 或 `model: "openai/gpt-4o-mini"`
- 串流輸出：`application/x-ndjson`，每行一個 JSON（友善前端與命令列）
- 內建腳本：快速測 Llama / OpenAI（串流/非串流）
- 可選傳入 Ollama `options`（例如 `num_predict`、`num_thread`）

## 📦 專案結構
```

.
├── docker-compose.yaml
├── gateway/
│   ├── main.py                # FastAPI：/api/chat（串流→NDJSON）
│   └── requirements.txt       # 固定套件版本，啟動更穩定
├── scripts/
│   ├── llm/                   # 測試腳本（llama/openai、stream/non-stream、all）
│   └── pull-model.sh 等       #（如有）
├── ollama/                    # Ollama 資料目錄（模型快取）
└── README.md

````

## 🧰 需求
- Ubuntu 22.04+ / macOS / WSL2
- Docker 24+
- （可選）有網路拉模型 / OpenAI 金鑰

## 🚀 快速開始
1. 建 `.env`（如需）：
   ```env
   # Gateway 讀取的 OpenAI 金鑰（若只用 Llama 可略）
   OPENAI_API_KEY=sk-xxxx

   # Gateway 打 Ollama（容器內建議用服務名）
   OLLAMA_BASE_URL=http://ollama:11434

   # 預設要自動拉取的模型
   DEFAULT_MODEL=llama3:instruct

   # CORS/ORIGINS（Ollama 本身）
   OLLAMA_ORIGINS=http://localhost,https://localhost,http://127.0.0.1
````

2. 啟動：

   ```bash
   docker compose up -d
   ```

   * `ollama` 容器會啟在 `:11434`
   * `gateway`（FastAPI/uvicorn）在 `:8082`
   * 若有 `models_init` 服務會自動 `pull DEFAULT_MODEL`

3. 驗證：

   ```bash
   curl -s http://localhost:8082/api/chat \
     -H 'Content-Type: application/json' \
     -d '{"model":"llama3:instruct","messages":[{"role":"user","content":"用一句話介紹你自己"}],"stream":false}'
   ```

## 🔌 API 說明

### POST `/api/chat`

**Request (JSON)**：

```json
{
  "model": "llama3:instruct",
  "messages": [
    {"role":"system","content":"請用繁體中文（台灣用語）。"},
    {"role":"user","content":"幫我寫三句客服問候語"}
  ],
  "stream": false,
  "options": {
    "num_predict": 128,
    "num_thread": 8
  }
}
```

**非串流回應（`stream:false`）**：

```json
{
  "model": "llama3:instruct",
  "created_at": "2025-08-08T08:27:50.537Z",
  "message": { "role": "assistant", "content": "..." },
  "done": true
}
```

**串流回應（`stream:true`，`content-type: application/x-ndjson`）**：
每行一個 JSON，逐 token 輸出：

```json
{"model":"llama3:instruct","message":{"role":"assistant","content":"您"},"done":false}
{"model":"llama3:instruct","message":{"role":"assistant","content":"好"},"done":false}
...
{"done":true}
```

> 備註：若上游是 OpenAI，Gateway 會把 SSE 轉成 NDJSON，兩邊行為一致。

## ⚙️ 常用環境變數

* `OPENAI_API_KEY`：使用 OpenAI 必填
* `OLLAMA_BASE_URL`（預設 `http://ollama:11434`）：Gateway → Ollama
* `DEFAULT_MODEL`（例：`llama3:instruct`）：啟動時自動 pull
* `OLLAMA_ORIGINS`：Ollama 的 CORS 白名單
* `GATEWAY`：腳本預設的 Gateway 基底 URL（例：`http://localhost:8082`）

## 🧪 腳本測試（命令列）

到 `scripts/llm/` 目錄，詳見下方 `scripts/README.md`。最常用：

```bash
scripts/llm/all.sh "給我三個客服問候語"
```

## 🔒 安全建議

* 對 Gateway 增加 `X-API-Key` 驗證（可在 `gateway/main.py` 擴充）
* 限制 `OLLAMA_ORIGINS` 與 Docker 對外 Port
* 若上雲，建議放反向代理（TLS、速率限制、IP allowlist）

## 🛠️ 疑難排除

* **第一次非串流很慢**：CPU 推論載入模型耗時，之後會快很多
* **`curl (18)`**：串流收尾時機造成，屬常見雜訊；只要其間有資料即可忽略
* **拉不到模型**：檢查 DNS / IPv4 強制 / `extra_hosts` 對 `registry.ollama.ai`
* 看日誌：

  ```bash
  docker compose logs -f gateway
  docker compose logs -f ollama
  ```

---

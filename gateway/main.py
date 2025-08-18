import os, json
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse, PlainTextResponse
import httpx

app = FastAPI()

OLLAMA = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
OPENAI_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_URL = "https://api.openai.com/v1/chat/completions"

NDJSON_HEADERS = {
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no",
}

# ============================================================
# 🧩 統一工具呼叫格式 (OpenAI V1/V2 → tool_calls 陣列)
# ============================================================
def normalize_tool_calls(delta):
    """
    輸入: OpenAI delta
    回傳: {"tool_calls": [ ... ]} 或 None
    """

    # ------- V1 function_call -------
    if "function_call" in delta and delta["function_call"]:
        fn = delta["function_call"]
        return {
            "tool_calls": [
                {
                    "id": None,
                    "type": "function",
                    "function": {
                        "name": fn.get("name"),
                        "arguments": fn.get("arguments"),
                    }
                }
            ]
        }

    # ------- V2 tool_calls -------
    if "tool_calls" in delta and delta["tool_calls"]:
        calls = []
        for t in delta["tool_calls"]:
            if t.get("type") == "function":
                calls.append({
                    "id": t.get("id"),
                    "type": "function",
                    "function": {
                        "name": t["function"].get("name"),
                        "arguments": t["function"].get("arguments"),
                    }
                })
        return {"tool_calls": calls} if calls else None

    return None


# ============================================================
#  OpenAI Streaming (patched → old + new)
# ============================================================
async def stream_openai(
    model: str,
    messages: list,
    options: dict | None = None,
    tools: list | None = None,
    tool_choice: str | dict | None = None,
):
    if not OPENAI_KEY:
        yield json.dumps({"error": "OPENAI_API_KEY missing"}) + "\n"
        return

    payload = {
        "model": model,
        "messages": messages,
        "stream": True,
    }

    if options and "temperature" in options:
        payload["temperature"] = options["temperature"]

    if tools is not None:
        payload["tools"] = tools

    if tool_choice is not None:
        payload["tool_choice"] = tool_choice

    headers = {
        "Authorization": f"Bearer {OPENAI_KEY}",
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
    }

    async with httpx.AsyncClient(timeout=None) as s:
        async with s.stream("POST", OPENAI_URL, headers=headers, json=payload) as r:
            async for line in r.aiter_lines():
                if not line or not line.startswith("data:"):
                    continue

                data = line[5:].strip()
                if data == "[DONE]":
                    break

                try:
                    chunk = json.loads(data)
                except:
                    continue

                delta = chunk["choices"][0].get("delta", {})
                if not delta:
                    continue

                # ===== A) 舊格式：{"message": {...}} =====
                if "content" in delta and delta["content"] is not None:
                    yield json.dumps({
                        "message": {
                            "role": "assistant",
                            "content": delta["content"]
                        }
                    }) + "\n"

                # ===== B) 統一工具呼叫格式 =====
                tc = normalize_tool_calls(delta)
                if tc:
                    yield json.dumps(tc) + "\n"

        yield json.dumps({"done": True}) + "\n"


# ============================================================
#  Ollama Streaming（保持原樣）
# ============================================================
async def stream_ollama(body: dict):
    async with httpx.AsyncClient(timeout=None) as s:
        async with s.stream("POST", f"{OLLAMA}/api/chat", json=body) as r:
            async for line in r.aiter_lines():
                if not line:
                    continue
                yield line + "\n"
        yield json.dumps({"done": True}) + "\n"


# ============================================================
#  Routes
# ============================================================
@app.get("/")
async def root():
    return PlainTextResponse("ok")


@app.post("/api/chat")
async def chat(req: Request):
    try:
        body = await req.json()
    except Exception:
        return JSONResponse({"error": "invalid json body"}, status_code=400)

    print("🔥 Gateway 收到：", body)

    model = (body.get("model") or "").strip()
    messages = body.get("messages") or []
    stream = bool(body.get("stream"))
    options = body.get("options")

    tools = body.get("tools")
    tool_choice = body.get("tool_choice")


    # =============================================================
    # OpenAI Provider
    # =============================================================
    if model.startswith("openai/"):
        true_model = model.split("/", 1)[1]

        # ---------------------------------------------------------
        # 非串流模式 (含 tool_calls)
        # ---------------------------------------------------------
        if not stream:
            if not OPENAI_KEY:
                return JSONResponse({"error": "OPENAI_API_KEY missing"}, status_code=400)

            payload = {"model": true_model, "messages": messages}

            if tools is not None:
                payload["tools"] = tools

            if tool_choice is not None:
                payload["tool_choice"] = tool_choice

            if options and "temperature" in options:
                payload["temperature"] = options["temperature"]

            async with httpx.AsyncClient(timeout=60.0) as s:
                r = await s.post(
                    OPENAI_URL,
                    headers={"Authorization": f"Bearer {OPENAI_KEY}"},
                    json=payload
                )
                data = r.json()

            msg = data["choices"][0].get("message", {})

            # 標準化 tool_calls
            tc = normalize_tool_calls(msg)

            result = {
                "model": model,
                "message": {
                    "role": "assistant",
                    "content": msg.get("content")
                },
                "tool_calls": tc.get("tool_calls") if tc else None,
                "done": True
            }

            return JSONResponse(result)

        # ---------------------------------------------------------
        # 串流模式
        # ---------------------------------------------------------
        async def gen():
            async for chunk in stream_openai(
                true_model,
                messages,
                options=options,
                tools=tools,
                tool_choice=tool_choice
            ):
                yield chunk

        return StreamingResponse(gen(), media_type="application/x-ndjson", headers=NDJSON_HEADERS)

    # =============================================================
    # Ollama Provider
    # =============================================================
    if not stream:
        async with httpx.AsyncClient(timeout=60.0) as s:
            r = await s.post(f"{OLLAMA}/api/chat", json=body)
            return JSONResponse(r.json(), status_code=r.status_code)

    async def gen():
        async for line in stream_ollama(body):
            yield line

    return StreamingResponse(gen(), media_type="application/x-ndjson", headers=NDJSON_HEADERS)
import os, json, asyncio
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse, PlainTextResponse
import httpx

app = FastAPI()

OLLAMA = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
OPENAI_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_URL = "https://api.openai.com/v1/chat/completions"

NDJSON_HEADERS = {
    "Cache-Control":"no-cache",
    "Connection":"keep-alive",
    "X-Accel-Buffering":"no",
}

async def stream_ollama(body: dict):
    async with httpx.AsyncClient(timeout=None) as s:
        async with s.stream("POST", f"{OLLAMA}/api/chat", json=body) as r:
            async for line in r.aiter_lines():
                if not line:
                    continue
                # ollama 原生就是 NDJSON：每行都是 {"message":{"content":"..."}}
                yield line + "\n"
            # 收尾：保險送一個 done
            yield json.dumps({"done": True}) + "\n"

async def stream_openai(model: str, messages: list, options: dict | None):
    if not OPENAI_KEY:
        yield json.dumps({"error":"OPENAI_API_KEY missing"}) + "\n"
        return
    payload = {
        "model": model,
        "messages": messages,
        "stream": True,
    }
    # 你若要把 options 映射到 OpenAI（例如温度），可在這裡轉
    if options:
        if "temperature" in options:
            payload["temperature"] = options["temperature"]

    headers = {
        "Authorization": f"Bearer {OPENAI_KEY}",
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
    }
    async with httpx.AsyncClient(timeout=None) as s:
        async with s.stream("POST", OPENAI_URL, headers=headers, json=payload) as r:
            async for line in r.aiter_lines():
                if not line:
                    continue
                if line.startswith("data:"):
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        chunk = json.loads(data)
                    except Exception:
                        continue
                    # 取增量 content，轉成 NDJSON 統一格式
                    out = None
                    for ch in chunk.get("choices", []):
                        delta = ch.get("delta") or {}
                        if "content" in delta and delta["content"] is not None:
                            out = delta["content"]
                            break
                    if out is not None:
                        yield json.dumps({
                            "model": model,
                            "message": {"role":"assistant","content": out},
                            "done": False
                        }) + "\n"
            # 收尾
            yield json.dumps({"done": True}) + "\n"

@app.get("/")
async def root():
    return PlainTextResponse("ok")

@app.post("/api/chat")
async def chat(req: Request):
    try:
        body = await req.json()
    except Exception:
        # 有時候客戶端出包傳了 bool/null
        return JSONResponse({"error":"invalid json body"}, status_code=400)

    model = (body.get("model") or "").strip()
    messages = body.get("messages") or []
    stream = bool(body.get("stream"))
    options = body.get("options")

    # 判斷 provider
    if model.startswith("openai/"):
        true_model = model.split("/",1)[1]
        if not stream:
            # 非串流：直接打 OpenAI 回原生，再盡量兼容你的客戶端
            if not OPENAI_KEY:
                return JSONResponse({"error":"OPENAI_API_KEY missing"}, status_code=400)
            payload = {"model": true_model, "messages": messages, "stream": False}
            if options and "temperature" in options:
                payload["temperature"] = options["temperature"]
            async with httpx.AsyncClient(timeout=60.0) as s:
                r = await s.post(OPENAI_URL,
                                 headers={"Authorization": f"Bearer {OPENAI_KEY}"},
                                 json=payload)
                if r.status_code >= 400:
                    return JSONResponse({"error":r.text}, status_code=r.status_code)
                data = r.json()
                # 盡量轉成統一結構（也保留原生 choices 以防你要）
                content = None
                try:
                    content = data["choices"][0]["message"]["content"]
                except Exception:
                    pass
                return JSONResponse({
                    "model": model,
                    "created_at": data.get("created"),
                    "message": {"role":"assistant","content": content} if content else None,
                    "choices": data.get("choices"),
                    "done": True
                })
        else:
            async def gen():
                async for chunk in stream_openai(true_model, messages, options):
                    yield chunk
            return StreamingResponse(gen(), media_type="application/x-ndjson", headers=NDJSON_HEADERS)

    # 否則一律走 ollama
    if not stream:
        async with httpx.AsyncClient(timeout=60.0) as s:
            r = await s.post(f"{OLLAMA}/api/chat", json=body)
            return JSONResponse(r.json(), status_code=r.status_code)
    else:
        async def gen():
            async for line in stream_ollama(body):
                yield line
        return StreamingResponse(gen(), media_type="application/x-ndjson", headers=NDJSON_HEADERS)

# ./gateway/Dockerfile
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8082

WORKDIR /app

# 先安裝系統相依（視你的 requirements 而定，先給常見基礎）
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl && \
    rm -rf /var/lib/apt/lists/*

# 先複製 requirements 以善用 Docker layer cache
COPY requirements.txt /app/requirements.txt
RUN python -m pip install --upgrade pip && \
    pip install -r /app/requirements.txt

# 再複製應用程式原始碼
COPY . /app

# 建立非 root 使用者（更安全）
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8082

# 若你的入口為 main.py 的 FastAPI app： main:app
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8082"]

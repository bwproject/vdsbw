#!/bin/bash

set -e

BASE_DIR="/root/docker/tg-zapret"
REPO="https://github.com/Flowseal/tg-ws-proxy.git"

echo "📦 Установка tg-zapret..."

# 1. Проверка Docker
command -v docker >/dev/null 2>&1 || { echo "❌ Docker не установлен"; exit 1; }
command -v docker compose >/dev/null 2>&1 || { echo "❌ Docker Compose не установлен"; exit 1; }

# 2. Создаём базовую папку
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# 3. Клонируем ВНУТРЬ tg-ws-proxy (ВАЖНО)
if [ -d "tg-ws-proxy" ]; then
  echo "⚠️ tg-ws-proxy уже существует → обновляем"
  cd tg-ws-proxy
  git pull
  cd ..
else
  echo "📥 Клонируем репозиторий..."
  git clone "$REPO" tg-ws-proxy
fi

# 4. Создаём docker-compose.yml В КОРНЕ tg-zapret
cat > docker-compose.yml <<'EOF'
version: "3.9"

services:
  tg-zapret:
    build:
      context: ./tg-ws-proxy
    container_name: tg-zapret
    restart: always
    network_mode: host

    command: >
      python -m tg_ws_proxy
      --host 0.0.0.0
      --port 3980
      --secret cae3e38eb2e196fb48cacb49de344823
      --dc-ip 2 149.154.167.220
      --dc-ip 4 149.154.167.220
      --fake-tls-domain les.projectbw.ru
      --cfproxy-domain projectbw.ru
      -v
EOF

# 5. Сборка и запуск
echo "🔧 build..."
docker compose build

echo "🚀 up..."
docker compose up -d

# 6. Проверка
echo "📊 status:"
docker ps | grep tg-zapret || true

echo "✅ DONE"
echo "📁 $BASE_DIR"

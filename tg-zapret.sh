#!/bin/bash

set -e

BASE="/root/docker/tg-zapret"
REPO="https://github.com/Flowseal/tg-ws-proxy.git"

echo "📦 Установка tg-zapret..."

# 1. Проверки
command -v docker >/dev/null 2>&1 || { echo "❌ Docker не установлен"; exit 1; }
command -v docker compose >/dev/null 2>&1 || { echo "❌ Docker Compose не установлен"; exit 1; }

# 2. Создаём папку
mkdir -p "$BASE"
cd "$BASE"

echo "📁 Перешли в $BASE"

# 3. СНАЧАЛА создаём docker-compose.yml
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

echo "📝 docker-compose.yml создан"

# 4. Потом клонируем в нужную папку
if [ -d "tg-ws-proxy" ]; then
  echo "⚠️ tg-ws-proxy уже существует → обновляем"
  cd tg-ws-proxy
  git pull
  cd ..
else
  echo "📥 Клонируем репозиторий..."
  git clone "$REPO" tg-ws-proxy
fi

echo "📦 Репозиторий готов"

# 5. Сборка
echo "🔧 build..."
docker compose build

# 6. Запуск
echo "🚀 up..."
docker compose up -d

# 7. Проверка
echo "📊 status:"
docker ps | grep tg-zapret || true

echo "✅ ГОТОВО"
echo "📁 $BASE"

#!/bin/bash

set -e

INSTALL_DIR="/root/docker/tg-zapret"
REPO="https://github.com/Flowseal/tg-ws-proxy.git"

echo "📦 Установка tg-zapret в $INSTALL_DIR"

# 1. Проверка Docker
if ! command -v docker &> /dev/null; then
  echo "❌ Docker не установлен"
  exit 1
fi

if ! command -v docker compose &> /dev/null; then
  echo "❌ docker compose не установлен"
  exit 1
fi

# 2. Создаём директорию
mkdir -p /root/docker
cd /root/docker

# 3. Клонируем репо
if [ -d "$INSTALL_DIR" ]; then
  echo "⚠️ Папка уже существует, обновляем..."
  cd "$INSTALL_DIR"
  git pull
else
  git clone "$REPO" tg-zapret
  cd tg-zapret
fi

# 4. Создаём docker-compose.yml
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

# 5. Сборка
echo "🔧 Сборка контейнера..."
docker compose build

# 6. Запуск
echo "🚀 Запуск..."
docker compose up -d

# 7. Проверка
echo "📊 Статус:"
docker ps | grep tg-zapret || true

echo "✅ Готово!"
echo "📁 Путь: $INSTALL_DIR"

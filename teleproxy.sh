#!/bin/bash

set -e

echo "[+] Проверка зависимостей..."

# Проверка Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "[!] Docker не установлен"
    exit 1
fi

# Установка OpenSSL если нет
if ! command -v openssl >/dev/null 2>&1; then
    echo "[+] OpenSSL не найден, устанавливаю..."

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y openssl
fi

# Проверка curl (нужен для healthcheck и IP)
if ! command -v curl >/dev/null 2>&1; then
    echo "[+] curl не найден, устанавливаю..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl
fi

echo

# Ввод домена
read -p "Введите домен для Fake-TLS (EE_DOMAIN): " EE_DOMAIN

if [ -z "$EE_DOMAIN" ]; then
    echo "[!] Домен не указан"
    exit 1
fi

# Генерация секрета
SECRET=$(openssl rand -hex 16)

echo "[+] SECRET: $SECRET"

# Создание директорий
mkdir -p /root/docker/teleproxy/data

# Docker compose
cat > /root/docker/teleproxy/docker-compose.yml << EOF
services:
  teleproxy:
    image: ghcr.io/teleproxy/teleproxy:latest
    platform: linux/amd64
    container_name: teleproxy
    ports:
      - "8884:443"
      - "8885:8888"
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    environment:
      - SECRET=${SECRET}
      - PORT=443
      - STATS_PORT=8888
      - WORKERS=1
      - RANDOM_PADDING=true
      - EE_DOMAIN=${EE_DOMAIN}
    volumes:
      - ./data:/opt/teleproxy/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8888/stats || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF

echo "[+] Запускаю контейнер..."

cd /root/docker/teleproxy

docker compose pull
docker compose up -d

echo "[+] Ожидание запуска..."
sleep 10

IP=$(curl -4 -s ifconfig.me)

echo
echo "========================================="
echo " TeleProxy установлен"
echo "========================================="
echo "IP:        $IP"
echo "PORT:      8884"
echo "DOMAIN:    $EE_DOMAIN"
echo "SECRET:    $SECRET"
echo "========================================="
echo

echo "[+] Последние логи:"
docker logs --tail 30 teleproxy || true

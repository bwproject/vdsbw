#!/bin/bash

set -e

if ! command -v openssl >/dev/null 2>&1; then
    echo "[+] Устанавливаю openssl..."
    apt-get update
    apt-get install -y openssl
fi

read -p "Введите домен для Fake-TLS (например mirror.yandex.ru): " EE_DOMAIN

if [ -z "$EE_DOMAIN" ]; then
    echo "Ошибка: домен не указан"
    exit 1
fi

SECRET=$(head -c 16 /dev/urandom | xxd -ps)

mkdir -p /root/docker/teleproxy/data

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

ufw allow 8884/tcp 2>/dev/null || true
ufw allow 8885/tcp 2>/dev/null || true

cd /root/docker/teleproxy

docker compose pull
docker compose up -d

sleep 10

IP=$(curl -4 -s ifconfig.me)

echo
echo "========================================="
echo " TeleProxy успешно установлен"
echo "========================================="
echo "IP:        ${IP}"
echo "PORT:      8884"
echo "DOMAIN:    ${EE_DOMAIN}"
echo "SECRET:    ${SECRET}"
echo

echo "=== docker-compose.yml ==="
cat docker-compose.yml

echo
echo "=== Логи ==="
docker logs --tail 30 teleproxy

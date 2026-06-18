#!/bin/bash

set -e

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTAINER_NAME="mtproto-proxy"
INSTALL_DIR="/root/docker/mtproto"
PORT="8443"
FAKE_DOMAIN="ya.ru"

echo "🚀 Установка MTProto Proxy (Docker Compose)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "📌 Fake TLS домен: ${BLUE}${FAKE_DOMAIN}${NC}"

# Проверка Docker
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker не установлен${NC}"
    exit 1
fi

# Проверка Docker Compose
if ! docker compose version >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker Compose не установлен${NC}"
    exit 1
fi

# Проверка OpenSSL
if ! command -v openssl >/dev/null 2>&1; then
    echo "[+] Устанавливаю OpenSSL..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y openssl
fi

# Проверка curl
if ! command -v curl >/dev/null 2>&1; then
    echo "[+] Устанавливаю curl..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl
fi

echo
echo -n "🔑 Генерация Fake TLS секрета..."

# HEX без xxd (чистый bash + od)
DOMAIN_HEX=$(echo -n "${FAKE_DOMAIN}" | od -An -tx1 | tr -d ' \n')

echo
echo "   Hex домена: ${DOMAIN_HEX}"

DOMAIN_LEN=${#DOMAIN_HEX}
NEEDED=$((30 - DOMAIN_LEN))
RANDOM_HEX=$(openssl rand -hex 15 | cut -c1-${NEEDED})

SECRET="ee${DOMAIN_HEX}${RANDOM_HEX}"

echo "   Случайное дополнение: ${RANDOM_HEX}"
echo -e "   Секрет: ${YELLOW}${SECRET}${NC}"
echo "   Длина: ${#SECRET} символов"

echo
echo -n "🔍 Проверка порта ${PORT}... "

if ss -tuln | grep -q ":${PORT} "; then
    echo -e "${YELLOW}порт занят${NC}"

    for alt_port in 2444 2445 2446; do
        if ! ss -tuln | grep -q ":${alt_port} "; then
            PORT=$alt_port
            echo "   Используем порт: ${PORT}"
            break
        fi
    done
else
    echo -e "${GREEN}свободен${NC}"
fi

mkdir -p "${INSTALL_DIR}"

cat > "${INSTALL_DIR}/docker-compose.yml" <<EOF
services:
  mtproto:
    image: telegrammessenger/proxy:latest
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "${PORT}:443"
    environment:
      SECRET: "${SECRET}"
EOF

echo
echo "📦 Запуск контейнера..."

cd "${INSTALL_DIR}"

docker compose down >/dev/null 2>&1 || true
docker compose pull
docker compose up -d

echo
echo "⏳ Ожидание запуска..."
sleep 5

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then

    SERVER_IP=$(curl -4 -s ifconfig.me)

    echo
    echo -e "${GREEN}✅ MTProto Proxy успешно запущен${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌐 Сервер: ${SERVER_IP}"
    echo "🔌 Порт: ${PORT}"
    echo "🔑 Секрет: ${SECRET}"
    echo "🌐 Fake TLS домен: ${FAKE_DOMAIN}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔗 Telegram:"
    echo "tg://proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}"
    echo "https://t.me/proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cat > "${INSTALL_DIR}/mtproto_config.txt" <<EOF
SERVER=${SERVER_IP}
PORT=${PORT}
SECRET=${SECRET}
DOMAIN=${FAKE_DOMAIN}
LINK=tg://proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}
EOF

    echo "💾 Конфигурация сохранена:"
    echo "   ${INSTALL_DIR}/mtproto_config.txt"

    echo
    echo "📋 Последние логи:"
    docker logs --tail 10 ${CONTAINER_NAME} || true

else
    echo -e "${RED}❌ Контейнер не запустился${NC}"
    docker logs ${CONTAINER_NAME}
    exit 1
fi

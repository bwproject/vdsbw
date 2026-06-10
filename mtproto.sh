#!/bin/bash

set -e

read -p "Введите порт для MTProto: " PORT

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "Ошибка: некорректный порт"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "[!] Docker не установлен"
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "[+] Устанавливаю openssl..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y openssl
    elif command -v apt >/dev/null 2>&1; then
        apt install -y openssl
    else
        echo "[!] Не удалось установить openssl автоматически"
        exit 1
    fi
fi

SECRET="ee$(openssl rand -hex 15)"

mkdir -p /root/docker/mtproxy

cat > /root/docker/mtproxy/docker-compose.yml << EOF
services:
  mtproxy:
    image: ghcr.io/cmzmozg/mtproxy-patched:latest
    container_name: mtproxy
    restart: always
    network_mode: host
    environment:
      - MT_PORT=${PORT}
      - MT_SECRET=${SECRET}
      - MT_TLS_DOMAIN=mirror.yandex.ru
EOF

echo "[+] Открываю порт ${PORT}/tcp"
ufw allow ${PORT}/tcp 2>/dev/null || true

echo "[+] Загружаю образ..."
cd /root/docker/mtproxy

docker compose pull
docker compose up -d

echo "[+] Ожидание запуска контейнера..."
sleep 5

IP=$(curl -4 -s ifconfig.me)

echo
echo "=========================================="
echo " MTProxy успешно установлен"
echo "=========================================="
echo "IP:      ${IP}"
echo "PORT:    ${PORT}"
echo "SECRET:  ${SECRET}"
echo

echo "=== Ссылка из логов ==="
docker logs mtproxy 2>&1 | grep "tg://proxy" | head -1 || true

echo
echo "=== Ручная ссылка ==="
echo "tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
echo

echo "=== docker-compose.yml ==="
cat /root/docker/mtproxy/docker-compose.yml

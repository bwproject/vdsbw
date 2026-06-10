#!/bin/bash

set -e

read -p "Введите порт для MTProto: " PORT

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "Ошибка: некорректный порт"
    exit 1
fi

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
      - MT_SECRET=auto
      - MT_TLS_DOMAIN=mirror.yandex.ru
EOF

echo "[+] Открываю порт ${PORT} в UFW..."
ufw allow ${PORT}/tcp 2>/dev/null || true

echo "[+] Запускаю MTProxy..."
cd /root/docker/mtproxy

docker compose pull
docker compose up -d

echo "[+] Ожидание запуска контейнера..."
sleep 5

IP=$(curl -4 -s ifconfig.me)

echo
echo "=== Ссылка для подключения ==="
docker logs mtproxy 2>&1 | grep "tg://proxy" | grep "${IP}" | head -1 || true

echo
echo "=== Последние логи ==="
docker logs --tail 20 mtproxy

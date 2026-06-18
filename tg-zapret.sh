#!/bin/bash

set -e

BASE="/root/docker/tg-zapret"
REPO="https://github.com/Flowseal/tg-ws-proxy.git"

echo "📦 Installing tg-zapret..."

command -v docker >/dev/null 2>&1 || { echo "❌ Docker not installed"; exit 1; }
command -v docker compose >/dev/null 2>&1 || { echo "❌ Docker Compose not installed"; exit 1; }

mkdir -p "$BASE"
cd "$BASE"

echo "📁 Working dir: $BASE"

# ----------------------------
# docker-compose
# ----------------------------
cat > docker-compose.yml <<'EOF'
version: "3.9"

services:
  tg-zapret:
    build: ./tg-ws-proxy
    container_name: tg-zapret
    restart: always
    ports:
      - "1443:1443"
    command: >
        --host 0.0.0.0
        --port 1443
        --secret cae3e38eb2e196fb48cacb49de344823
        --dc-ip 2:149.154.167.220
        --dc-ip 4:149.154.167.220
        --dc-ip 203:91.105.192.100
        --fake-tls-domain github.com
        --cfproxy-domain projectbw.ru
        -v
EOF

echo "📝 docker-compose created"

# ----------------------------
# clone repo
# ----------------------------
if [ -d "tg-ws-proxy" ]; then
  echo "♻️ updating repo..."
  cd tg-ws-proxy
  git pull
  cd ..
else
  echo "📥 cloning repo..."
  git clone "$REPO" tg-ws-proxy
fi

echo "📦 repo ready"

# ----------------------------
# build + up
# ----------------------------
echo "🔧 building..."
docker compose build

echo "🚀 starting..."
docker compose up -d

cd "$BASE"

# ----------------------------
# logs parsing
# ----------------------------
echo "⏳ waiting for service..."
sleep 3

echo ""
echo "================ CONNECT INFO ================"

docker logs tg-zapret 2>&1 | grep -E "Connect:|tg://proxy|Listening|Secret" | tail -n 20

echo "============================================="
echo ""
echo "📊 live logs (Ctrl+C to exit):"

docker compose logs -f

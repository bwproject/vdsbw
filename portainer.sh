#!/bin/bash

DIR="/root/docker/portainer-agent"
STACK_NAME="portainer_agent"

function install_standalone() {
  echo "== Установка Portainer Agent (Standalone Docker Compose) =="

  mkdir -p "$DIR"
  cd "$DIR"

  cat > docker-compose.yml <<'EOF'
version: "3.9"

services:
  portainer_agent:
    image: portainer/agent:2.39.1
    container_name: portainer_agent
    restart: always
    ports:
      - "9001:9001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
      - /:/host
EOF

  docker compose up -d

  echo "✔ Standalone Agent установлен (порт 9001)"
}

function remove_standalone() {
  echo "== Удаление Standalone Portainer Agent =="

  cd "$DIR" 2>/dev/null || true

  docker compose down 2>/dev/null || true
  docker rm -f portainer_agent 2>/dev/null || true

  echo "✔ Standalone Agent удалён"
}

function install_swarm() {
  echo "== Установка Portainer Agent (Swarm режим) =="

  if ! docker info | grep -q "Swarm: active"; then
    echo "Swarm не активен → инициализация..."
    docker swarm init
  fi

  docker network ls | grep -q portainer_agent_network || \
  docker network create --driver overlay --attachable portainer_agent_network

  cat > /tmp/portainer-agent-stack.yml <<'EOF'
version: "3.9"

networks:
  portainer_agent_network:
    driver: overlay
    attachable: true

services:
  portainer_agent:
    image: portainer/agent:2.39.1
    deploy:
      mode: global
      placement:
        constraints:
          - node.platform.os == linux
    ports:
      - target: 9001
        published: 9001
        protocol: tcp
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
      - /:/host
    networks:
      - portainer_agent_network
EOF

  docker stack deploy -c /tmp/portainer-agent-stack.yml "$STACK_NAME"

  echo "✔ Swarm Agent установлен (порт 9001)"
}

function remove_swarm() {
  echo "== Удаление Swarm Portainer Agent =="

  docker stack rm "$STACK_NAME" 2>/dev/null || true
  docker network rm portainer_agent_network 2>/dev/null || true

  echo "✔ Swarm Agent удалён"
}

while true; do
  echo ""
  echo "=============================="
  echo "     МЕНЮ PORTAINER AGENT"
  echo "=============================="
  echo "1) Установить (Standalone Docker Compose)"
  echo "2) Удалить (Standalone)"
  echo "3) Установить (Swarm режим)"
  echo "4) Удалить (Swarm)"
  echo "5) Выход"
  echo "=============================="

  read -p "Выберите пункт: " opt

  case $opt in
    1) install_standalone ;;
    2) remove_standalone ;;
    3) install_swarm ;;
    4) remove_swarm ;;
    5) echo "Выход..."; exit 0 ;;
    *) echo "❌ Неверный выбор" ;;
  esac
done
#!/bin/bash

DIR="/root/docker/portainer-node"
STACK_NAME="portainer"

function install_swarm() {
  echo "== Установка Portainer Swarm (Agent) =="

  mkdir -p "$DIR"
  cd "$DIR"

  cat > docker-compose.yml <<'EOF'
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
    networks:
      - portainer_agent_network
    ports:
      - target: 9001
        published: 9001
        protocol: tcp
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
      - /:/host
    environment:
      AGENT_CLUSTER_ADDR: tasks.portainer_agent
EOF

  if ! docker info | grep -q "Swarm: active"; then
    echo "Инициализация Swarm..."
    docker swarm init
  fi

  docker network ls | grep -q portainer_agent_network || \
  docker network create --driver overlay --attachable portainer_agent_network

  docker stack deploy -c docker-compose.yml "$STACK_NAME"

  echo "Swarm Portainer установлен"
}

function remove_swarm() {
  echo "== Удаление Portainer Swarm =="

  docker stack rm "$STACK_NAME" || true
  docker network rm portainer_agent_network || true

  echo "Swarm Portainer удалён"
}

function install_standalone() {
  echo "== Установка обычного Portainer =="

  mkdir -p "$DIR"
  cd "$DIR"

  cat > docker-compose.yml <<'EOF'
version: "3.9"

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - "9000:9000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

volumes:
  portainer_data:
EOF

  docker compose up -d

  echo "Standalone Portainer установлен"
}

function remove_standalone() {
  echo "== Удаление обычного Portainer =="

  cd "$DIR" || return
  docker compose down -v || true

  echo "Standalone Portainer удалён"
}

while true; do
  echo ""
  echo "=============================="
  echo "  PORTAINER INSTALL MENU"
  echo "=============================="
  echo "1) Установить Docker Portainer SWARM"
  echo "2) Удалить Docker Portainer SWARM"
  echo "3) Установить обычный Docker Portainer"
  echo "4) Удалить обычный Docker Portainer"
  echo "5) Выход"
  echo "=============================="
  read -p "Выберите опцию: " opt

  case $opt in
    1) install_swarm ;;
    2) remove_swarm ;;
    3) install_standalone ;;
    4) remove_standalone ;;
    5) echo "Выход..."; exit 0 ;;
    *) echo "Неверный выбор" ;;
  esac
done
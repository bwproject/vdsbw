#!/bin/bash

DIR="/root/docker/portainer-node"
STACK_NAME="portainer"

function install_swarm() {
  echo "== Установка Portainer SWARM (Agent) =="

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

  echo "Swarm Agent установлен"
}

function remove_swarm() {
  echo "== Удаление SWARM Portainer =="

  docker stack rm "$STACK_NAME" || true
  docker network rm portainer_agent_network || true

  echo "Swarm удалён"
}

function install_standalone() {
  echo "== Установка Portainer Agent (Standalone Docker) =="

  docker rm -f portainer_agent 2>/dev/null || true

  docker run -d \
    -p 9001:9001 \
    --name portainer_agent \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /var/lib/docker/volumes:/var/lib/docker/volumes \
    -v /:/host \
    portainer/agent:2.39.1

  echo "Standalone Agent установлен"
}

function remove_standalone() {
  echo "== Удаление Standalone Agent =="

  docker rm -f portainer_agent 2>/dev/null || true

  echo "Standalone Agent удалён"
}

while true; do
  echo ""
  echo "=============================="
  echo "      PORTAINER MENU"
  echo "=============================="
  echo "1) Установить SWARM Portainer Agent"
  echo "2) Удалить SWARM Portainer Agent"
  echo "3) Установить обычный Docker Portainer Agent"
  echo "4) Удалить обычный Docker Portainer Agent"
  echo "5) Выход"
  echo "=============================="
  read -p "Выбор: " opt

  case $opt in
    1) install_swarm ;;
    2) remove_swarm ;;
    3) install_standalone ;;
    4) remove_standalone ;;
    5) exit 0 ;;
    *) echo "Неверный выбор" ;;
  esac
done
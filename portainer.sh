#!/bin/bash

set -e

DIR="/root/docker/portainer-node"

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

echo "docker-compose.yml создан в $DIR"

# Проверка Swarm
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
  echo "Swarm не активен. Инициализируем..."
  docker swarm init
fi

# Создание сети (если уже есть — не падаем)
docker network ls | grep -q portainer_agent_network || \
docker network create \
  --driver overlay \
  --attachable \
  portainer_agent_network

echo "Готово. Теперь запуск:"
echo "cd $DIR && docker stack deploy -c docker-compose.yml portainer"

#!/bin/bash

set -e

echo "Обновление системы..."
apt update

echo "Установка зависимостей..."
apt install -y ca-certificates gnupg curl lsb-release

echo "Добавление Docker GPG ключа..."
mkdir -p /usr/share/keyrings

curl -fsSL https://download.docker.com/linux/debian/gpg \
| gpg --dearmor -o /usr/share/keyrings/docker.gpg

echo "Добавление репозитория Docker..."

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Установка Docker..."
apt update

apt install -y \
docker-ce \
docker-ce-cli \
containerd.io \
docker-buildx-plugin

echo "Docker установлен:"
docker --version

echo "Установка Docker Compose..."

mkdir -p /usr/local/lib/docker/cli-plugins/

curl -SL \
https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) \
-o /usr/local/lib/docker/cli-plugins/docker-compose

chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

echo "Docker Compose установлен:"
docker compose version

echo "Готово!"

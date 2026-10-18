#!/bin/bash

BASE_DIR="/hdd/compose"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Без цвета

# Проверка, что docker установлен и работает
if ! command -v docker &>/dev/null; then
  echo -e "${RED}Ошибка:${NC} Docker не установлен или не в PATH."
  exit 1
fi

if ! docker info &>/dev/null; then
  echo -e "${RED}Ошибка:${NC} Docker не запущен или нет доступа."
  exit 1
fi

function run_in_dirs() {
  local cmd=$1
  for dir in "$BASE_DIR"/*/; do
    if [ -f "$dir/docker-compose.yml" ]; then
      echo -e "${CYAN}>>> Выполняется в $dir:${NC} docker compose $cmd"
      (cd "$dir" && docker compose $cmd)
      echo
    else
      echo -e "${YELLOW}Пропущено (нет docker-compose.yml): $dir${NC}"
    fi
  done
}

while true; do
  echo -e "${GREEN}Выберите действие:${NC}"
  echo "1 — Запустить все контейнеры"
  echo "2 — Перезагрузить все контейнеры"
  echo "3 — Обновить образы"
  echo "4 — Показать статус всех контейнеров"
  echo "5 — Выйти"

  read -rp "Введите номер действия: " choice

  case "$choice" in
    1)
      echo -e "${GREEN}Запуск всех контейнеров...${NC}"
      run_in_dirs "up -d"
      ;;
    2)
      echo -e "${GREEN}Перезагрузка всех контейнеров...${NC}"
      run_in_dirs "down"
      run_in_dirs "up -d"
      ;;
    3)
      echo -e "${GREEN}Обновление образов...${NC}"
      run_in_dirs "pull"
      ;;
    4)
      echo -e "${GREEN}Статус всех контейнеров...${NC}"
      for dir in "$BASE_DIR"/*/; do
        if [ -f "$dir/docker-compose.yml" ]; then
          echo -e "${CYAN}>>> Статус в $dir:${NC}"
          (cd "$dir" && docker compose ps)
          echo
        else
          echo -e "${YELLOW}Пропущено (нет docker-compose.yml): $dir${NC}"
        fi
      done
      ;;
    5)
      echo -e "${GREEN}Выход.${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}Неверный выбор! Попробуйте снова.${NC}"
      ;;
  esac
done
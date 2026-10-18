#!/usr/bin/env bash

BASE_DIR="/hdd/compose"
SCRIPT_URL="https://raw.githubusercontent.com/bwproject/vdsbw/main/all.sh"
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Always fetch the latest version from GitHub before running any action.
# If GitHub cannot be reached, stop rather than silently running an outdated script.
auto_update() {
  local tmp downloader url
  tmp="$(mktemp)" || {
    echo -e "${RED}Ошибка:${NC} не удалось создать временный файл для обновления."
    exit 1
  }

  url="${SCRIPT_URL}?cache_bust=$(date +%s)-$$"
  echo -e "${CYAN}Принудительно загружаю актуальный all.sh с GitHub... ${NC}"

  if command -v curl >/dev/null 2>&1; then
    downloader="curl"
    if ! curl -fLsS --retry 2 --connect-timeout 10 --max-time 45 -H 'Cache-Control: no-cache' "$url" -o "$tmp"; then
      echo -e "${RED}Ошибка:${NC} не удалось скачать обновление с GitHub. Запуск отменён."
      rm -f "$tmp"
      exit 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    downloader="wget"
    if ! wget -q --tries=3 --timeout=45 --header='Cache-Control: no-cache' "$url" -O "$tmp"; then
      echo -e "${RED}Ошибка:${NC} не удалось скачать обновление с GitHub. Запуск отменён."
      rm -f "$tmp"
      exit 1
    fi
  else
    echo -e "${RED}Ошибка:${NC} нужен curl или wget для обязательного обновления."
    rm -f "$tmp"
    exit 1
  fi

  if [[ ! -s "$tmp" ]] || ! grep -q '^#!/usr/bin/env bash' "$tmp" || ! bash -n "$tmp"; then
    echo -e "${RED}Ошибка:${NC} скачанный all.sh пустой или не прошёл проверку. Запуск отменён."
    rm -f "$tmp"
    exit 1
  fi

  if cmp -s "$tmp" "$SELF_PATH"; then
    echo -e "${GREEN}Скрипт уже актуален (версия проверена на GitHub).${NC}"
    rm -f "$tmp"
    return 0
  fi

  if ! cp "$tmp" "$SELF_PATH"; then
    echo -e "${RED}Ошибка:${NC} не удалось обновить $SELF_PATH. Проверьте права доступа."
    rm -f "$tmp"
    exit 1
  fi
  chmod +x "$SELF_PATH"
  rm -f "$tmp"

  echo -e "${GREEN}Скрипт обновлён. Перезапускаю новую версию...${NC}"
  exec bash "$SELF_PATH" "$@"
}

auto_update "$@"
# Check Docker after updating.
if ! command -v docker >/dev/null 2>&1; then
  echo -e "${RED}Ошибка:${NC} Docker не установлен или не в PATH."
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo -e "${RED}Ошибка:${NC} Docker не запущен или нет доступа."
  exit 1
fi
if ! command -v screen >/dev/null 2>&1; then
  echo -e "${RED}Ошибка:${NC} screen не установлен. Установите его: apt-get install screen"
  exit 1
fi


# Run Compose commands directly, without creating screen sessions.
run_in_dirs_direct() {
  local dir
  local -a compose_args=( "$@" )
  local failed=0

  shopt -s nullglob
  local dirs=( "$BASE_DIR"/*/ )
  shopt -u nullglob

  for dir in "${dirs[@]}"; do
    if [[ -f "${dir}docker-compose.yml" || -f "${dir}compose.yml" || -f "${dir}compose.yaml" || -f "${dir}docker-compose.yaml" ]]; then
      echo -e "${CYAN}>>> ${dir}: docker compose ${compose_args[*]}${NC}"
      if ! (cd "$dir" && docker compose "${compose_args[@]}"); then
        echo -e "${RED}Ошибка выполнения в ${dir}${NC}"
        failed=1
      fi
      echo
    else
      echo -e "${YELLOW}Пропущено (нет compose-файла): ${dir}${NC}"
    fi
  done
  return "$failed"
}

# Execute each compose command in a temporary screen session named after its directory.
# Wait for the session to finish; for "up -d", Docker containers keep running independently.
run_in_dirs() {
  local dir name session
  local -a compose_args=( "$@" )
  local failed=0
  local -a sessions=()
  local -a session_names=()

  shopt -s nullglob
  local dirs=( "$BASE_DIR"/*/ )
  shopt -u nullglob

  # Start every Compose command in its own screen before waiting for any one command.
  for dir in "${dirs[@]}"; do
    if [[ -f "${dir}docker-compose.yml" || -f "${dir}compose.yml" || -f "${dir}compose.yaml" || -f "${dir}docker-compose.yaml" ]]; then
      name="$(basename "${dir%/}")"
      session="${name//[^a-zA-Z0-9_.-]/_}"

      if screen -ls 2>/dev/null | grep -Fq ".${session}"; then
        session="${session}_$RANDOM"
      fi

      echo -e "${CYAN}>>> Запускаю в screen ${session}: ${dir}docker compose ${compose_args[*]}${NC}"
      if screen -dmS "$session" bash -lc 'cd -- "$1" || exit 1; shift; "$@"' _ "$dir" docker compose "${compose_args[@]}"; then
        sessions+=( "$session" )
        session_names+=( "$name" )
      else
        echo -e "${RED}Не удалось создать screen для ${name}.${NC}"
        failed=1
      fi
    else
      echo -e "${YELLOW}Пропущено (нет compose-файла): ${dir}${NC}"
    fi
  done

  # Every folder has been launched; wait for all short-lived screen commands afterward.
  local i
  for i in "${!sessions[@]}"; do
    session="${sessions[$i]}"
    name="${session_names[$i]}"
    while screen -ls 2>/dev/null | grep -Fq ".${session}"; do
      sleep 0.2
    done
    echo -e "${GREEN}Готово: ${name}${NC}"
  done

  return "$failed"
}
show_status() {
  shopt -s nullglob
  local dirs=( "$BASE_DIR"/*/ )
  shopt -u nullglob
  local dir
  for dir in "${dirs[@]}"; do
    if [[ -f "${dir}docker-compose.yml" || -f "${dir}compose.yml" || -f "${dir}compose.yaml" || -f "${dir}docker-compose.yaml" ]]; then
      echo -e "${CYAN}>>> Статус в ${dir}:${NC}"
      (cd "$dir" && docker compose ps)
      echo
    fi
  done
}


show_status_screen() {
  local dir name session
  local failed=0
  local -a sessions=()
  local -a session_names=()
  shopt -s nullglob
  local dirs=( "$BASE_DIR"/*/ )
  shopt -u nullglob

  for dir in "${dirs[@]}"; do
    if [[ -f "${dir}docker-compose.yml" || -f "${dir}compose.yml" || -f "${dir}compose.yaml" || -f "${dir}docker-compose.yaml" ]]; then
      name="$(basename "${dir%/}")"
      session="${name//[^a-zA-Z0-9_.-]/_}_status"
      if screen -ls 2>/dev/null | grep -Fq ".${session}"; then
        session="${session}_$RANDOM"
      fi
      echo -e "${CYAN}>>> Статус в screen ${session}: ${dir}${NC}"
      if screen -dmS "$session" bash -lc 'cd -- "$1" || exit 1; docker compose ps' _ "$dir"; then
        sessions+=( "$session" )
        session_names+=( "$name" )
      else
        echo -e "${RED}Не удалось создать screen для ${name}.${NC}"
        failed=1
      fi
    fi
  done

  local i
  for i in "${!sessions[@]}"; do
    session="${sessions[$i]}"
    name="${session_names[$i]}"
    while screen -ls 2>/dev/null | grep -Fq ".${session}"; do
      sleep 0.2
    done
    echo -e "${GREEN}Статус получен: ${name}${NC}"
  done
  return "$failed"
}


run_action() {
  case "$1" in
    1) echo -e "${GREEN}Запуск всех контейнеров без screen...${NC}"; run_in_dirs_direct up -d ;;
    2) echo -e "${GREEN}Остановка всех контейнеров без screen...${NC}"; run_in_dirs_direct down ;;
    3) echo -e "${GREEN}Обновление образов без screen...${NC}"; run_in_dirs_direct pull ;;
    4) echo -e "${GREEN}Статус всех контейнеров без screen...${NC}"; show_status ;;
    5) echo -e "${GREEN}Выход.${NC}"; exit 0 ;;
    6) echo -e "${GREEN}Запуск всех контейнеров через screen...${NC}"; run_in_dirs up -d ;;
    7) echo -e "${GREEN}Остановка всех контейнеров через screen...${NC}"; run_in_dirs down ;;
    8) echo -e "${GREEN}Обновление образов через screen...${NC}"; run_in_dirs pull ;;
    9) echo -e "${GREEN}Статус всех контейнеров через screen...${NC}"; show_status_screen ;;
    10) echo -e "${GREEN}Выход.${NC}"; exit 0 ;;
    *) echo -e "${RED}Неверный выбор! Используйте 1–10.${NC}"; return 2 ;;
  esac
}

# If an argument is supplied, execute that menu option immediately.
if [[ -n "${1:-}" ]]; then
  run_action "$1"
  exit $?
fi

while true; do
  echo -e "${GREEN}Без screen:${NC}"
  echo "1 — Запустить все контейнеры"
  echo "2 — Остановить все контейнеры"
  echo "3 — Обновить образы"
  echo "4 — Показать статус всех контейнеров"
  echo "5 — Выйти"
  echo
  echo -e "${GREEN}Через screen:${NC}"
  echo "6 — Запустить все контейнеры"
  echo "7 — Остановить все контейнеры"
  echo "8 — Обновить образы"
  echo "9 — Показать статус всех контейнеров"
  echo "10 — Выйти"
  read -rp "Введите номер действия: " choice || exit 0
  run_action "$choice"
done

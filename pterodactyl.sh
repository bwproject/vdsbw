#!/bin/bash

set -e

echo "======================================"
echo "   Pterodactyl FULL Updater"
echo "   Panel + Wings"
echo "======================================"

# =========================
# ARG PARSER
# =========================
PANEL_PATH=""

for arg in "$@"; do
  case $arg in
    -panel=*)
      PANEL_PATH="${arg#*=}"
      ;;
  esac
done

# =========================
# DEFAULT PATHS
# =========================
DEFAULT_PATHS=(
  "/var/www/pterodactyl"
  "/srv/pterodactyl"
  "/var/www/pterodactyl/public"
)

UPDATE_PANEL=true

echo "[1/10] Поиск панели..."

# =========================
# AUTO DETECT PANEL
# =========================
if [ -z "$PANEL_PATH" ]; then
  for path in "${DEFAULT_PATHS[@]}"; do
    if [ -f "$path/artisan" ]; then
      PANEL_PATH="$path"
      echo "[+] Панель найдена: $PANEL_PATH"
      break
    fi
  done
fi

# =========================
# MANUAL INPUT IF NOT FOUND
# =========================
if [ -z "$PANEL_PATH" ]; then
  echo "[-] Панель не указана или не найдена"
  echo "👉 Введите путь к панели или нажмите ENTER чтобы пропустить:"
  read -rp "Путь к панели: " PANEL_PATH
fi

# =========================
# SKIP PANEL OPTION
# =========================
if [ -z "$PANEL_PATH" ]; then
  echo "[!] Панель пропущена — переходим к Wings"
  UPDATE_PANEL=false
fi

if [ "$UPDATE_PANEL" = true ]; then
  if [ ! -f "$PANEL_PATH/artisan" ]; then
    echo "[!] artisan не найден — панель пропущена"
    UPDATE_PANEL=false
  fi
fi

# =========================
# PANEL UPDATE
# =========================
if [ "$UPDATE_PANEL" = true ]; then

  echo "[2/10] Обновление панели..."
  cd "$PANEL_PATH"

  echo "[*] Maintenance mode..."
  php artisan down || true

  # =========================
  # GIT OR RELEASE
  # =========================
  if [ -d ".git" ]; then

    echo "[*] Git установка обнаружена"

    git fetch --all
    git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)

  else

    echo "[*] Release установка — скачивание архива"

    echo "[*] Downloading panel.tar.gz..."
    curl -fL --retry 3 --connect-timeout 15 \
      -o panel.tar.gz \
      https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz

    if [ ! -s panel.tar.gz ]; then
      echo "[!] Ошибка загрузки архива"
      exit 1
    fi

    echo "[*] Extracting..."
    tar -xzf panel.tar.gz

    rm -f panel.tar.gz
  fi

  # =========================
  # PERMISSIONS (IMPORTANT)
  # =========================
  echo "[*] Fixing permissions..."

  if id "www-data" &>/dev/null; then
    chown -R www-data:www-data "$PANEL_PATH"
  fi

  chmod -R u+rwX,g+rX,o-rwx \
    "$PANEL_PATH/storage" \
    "$PANEL_PATH/bootstrap/cache" \
    "$PANEL_PATH/public" || true

  # =========================
  # COMPOSER
  # =========================
  echo "[*] Installing dependencies..."
  composer install --no-dev --optimize-autoloader

  # =========================
  # MIGRATIONS
  # =========================
  echo "[*] Running migrations..."
  php artisan migrate --force

  # =========================
  # CACHE CLEAR
  # =========================
  echo "[*] Clearing cache..."
  php artisan cache:clear
  php artisan config:clear
  php artisan route:clear
  php artisan view:clear
  php artisan optimize:clear || true

  # =========================
  # QUEUE
  # =========================
  echo "[*] Restart queue..."
  php artisan queue:restart || true

  echo "[*] Bringing panel up..."
  php artisan up || true

  echo "[+] Panel update completed"

else
  echo "[2/10] Panel skipped"
fi

# =========================
# WINGS UPDATE
# =========================
echo "[3/10] Wings update..."

if systemctl list-units --type=service | grep -q wings; then
  echo "[*] Restarting Wings..."
  systemctl restart wings || true
  systemctl status wings --no-pager || true
else
  echo "[!] Wings service not found (Docker users must restart manually)"
fi

echo "======================================"
echo "   DONE"
echo "======================================"

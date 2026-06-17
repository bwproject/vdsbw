#!/bin/bash

set -e

echo "======================================"
echo "   Pterodactyl FULL Updater"
echo "   Panel + Wings (stable mode)"
echo "======================================"

# =========================
# СТАНДАРТНЫЕ ПУТИ
# =========================
DEFAULT_PATHS=(
  "/var/www/pterodactyl"
  "/srv/pterodactyl"
  "/var/www/pterodactyl/public"
)

PANEL_PATH=""
UPDATE_PANEL=true

echo "[1/9] Поиск панели..."

for path in "${DEFAULT_PATHS[@]}"; do
  if [ -f "$path/artisan" ]; then
    PANEL_PATH="$path"
    echo "[+] Панель найдена: $PANEL_PATH"
    break
  fi
done

# =========================
# РУЧНОЙ ВВОД
# =========================
if [ -z "$PANEL_PATH" ]; then
  echo "[-] Панель не найдена в стандартных путях."
  echo "👉 Введите путь к панели или нажмите ENTER чтобы пропустить:"
  read -rp "Путь к панели: " PANEL_PATH
fi

# =========================
# ПРОПУСК ПАНЕЛИ
# =========================
if [ -z "$PANEL_PATH" ]; then
  echo "[!] Панель пропущена — переходим к Wings"
  UPDATE_PANEL=false
fi

# проверка пути
if [ "$UPDATE_PANEL" = true ]; then
  if [ ! -f "$PANEL_PATH/artisan" ]; then
    echo "[!] Неверный путь (artisan не найден)"
    UPDATE_PANEL=false
  fi
fi

# =========================
# ОБНОВЛЕНИЕ ПАНЕЛИ
# =========================
if [ "$UPDATE_PANEL" = true ]; then

  echo "[2/9] Обновление панели..."
  cd "$PANEL_PATH"

  echo "[*] Maintenance mode..."
  php artisan down || true

  # =========================
  # GIT ИЛИ RELEASE
  # =========================
  if [ -d ".git" ]; then

    echo "[*] Git install — обновление через git"

    git fetch --all
    git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)

  else

    echo "[*] Release install — скачивание архива"

    echo "[*] Скачивание panel.tar.gz..."
    curl -fL --retry 3 --connect-timeout 15 \
      -o panel.tar.gz \
      https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz

    if [ ! -s panel.tar.gz ]; then
      echo "[!] Ошибка: файл не скачался"
      exit 1
    fi

    echo "[*] Распаковка..."
    tar -xzf panel.tar.gz

    rm -f panel.tar.gz
  fi

  # =========================
  # ПРАВА
  # =========================
  echo "[*] Выставляем права..."
  chmod -R 755 storage bootstrap/cache || true

  # =========================
  # COMPOSER
  # =========================
  echo "[*] Composer install..."
  composer install --no-dev --optimize-autoloader

  # =========================
  # MIGRATIONS
  # =========================
  echo "[*] Migrations..."
  php artisan migrate --force

  # =========================
  # CACHE CLEAN
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

  echo "[+] Panel updated successfully"

else
  echo "[2/9] Panel skipped"
fi

# =========================
# WINGS
# =========================
echo "[3/9] Updating Wings..."

if systemctl list-units --type=service | grep -q wings; then
  echo "[*] Restarting Wings via systemd..."
  systemctl restart wings || true
  systemctl status wings --no-pager || true
else
  echo "[!] Wings service not found"
  echo "    (If Docker — restart container manually)"
fi

echo "======================================"
echo "   UPDATE COMPLETED"
echo "======================================

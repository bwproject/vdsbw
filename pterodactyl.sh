#!/bin/bash

set -e

echo "======================================"
echo "   Pterodactyl FULL Updater (Panel + Wings)"
echo "======================================"

DEFAULT_PATHS=(
  "/var/www/pterodactyl"
  "/srv/pterodactyl"
  "/var/www/pterodactyl/public"
)

PANEL_PATH=""

echo "[1/7] Поиск панели в стандартных путях..."

for path in "${DEFAULT_PATHS[@]}"; do
  if [ -f "$path/artisan" ]; then
    PANEL_PATH="$path"
    echo "[+] Панель найдена: $PANEL_PATH"
    break
  fi
done

# если не нашли — спрашиваем
if [ -z "$PANEL_PATH" ]; then
  echo "[-] Панель не найдена в стандартных путях."
  echo "👉 Введите путь к панели или нажмите ENTER чтобы пропустить обновление панели:"
  read -rp "Путь к панели: " PANEL_PATH
fi

UPDATE_PANEL=true

# если пусто — пропускаем панель
if [ -z "$PANEL_PATH" ]; then
  echo "[!] Обновление панели пропущено. Переходим к Wings..."
  UPDATE_PANEL=false
else
  if [ ! -f "$PANEL_PATH/artisan" ]; then
    echo "[!] Неверный путь панели (artisan не найден). Пропускаем панель."
    UPDATE_PANEL=false
  fi
fi

# =========================
# ОБНОВЛЕНИЕ ПАНЕЛИ
# =========================
if [ "$UPDATE_PANEL" = true ]; then
  echo "[2/7] Обновление панели..."

  cd "$PANEL_PATH"

  echo "[*] Maintenance mode..."
  php artisan down || true

  echo "[*] Git update..."
  git fetch --all
  git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)

  echo "[*] Composer install..."
  composer install --no-dev --optimize-autoloader

  echo "[*] Migrations..."
  php artisan migrate --force

  echo "[*] Cache cleanup..."
  php artisan cache:clear
  php artisan config:clear
  php artisan route:clear
  php artisan view:clear
  php artisan optimize:clear || true

  echo "[*] Queue restart..."
  php artisan queue:restart || true

  echo "[*] Bringing panel up..."
  php artisan up || true

  echo "[+] Панель обновлена"
else
  echo "[2/7] Панель пропущена"
fi

# =========================
# ОБНОВЛЕНИЕ WINGS
# =========================

echo "[3/7] Обновление Wings..."

if command -v wings >/dev/null 2>&1; then
  echo "[*] Wings найден как бинарник"
fi

if systemctl list-units --type=service | grep -q wings; then
  echo "[*] Перезапуск Wings через systemctl..."
  systemctl restart wings || true
  systemctl status wings --no-pager || true
else
  echo "[!] Wings service не найден (systemctl)."
  echo "    Если у тебя Docker — перезапусти контейнер вручную."
fi

echo "======================================"
echo "   ГОТОВО: обновление завершено"
echo "======================================"

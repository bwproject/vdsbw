#!/bin/bash

set -e

echo "======================================"
echo "   Pterodactyl FULL Updater"
echo "   (Panel + Wings)"
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

echo "[1/8] Поиск панели в стандартных путях..."

for path in "${DEFAULT_PATHS[@]}"; do
  if [ -f "$path/artisan" ]; then
    PANEL_PATH="$path"
    echo "[+] Панель найдена: $PANEL_PATH"
    break
  fi
done

# =========================
# РУЧНОЙ ВВОД ПУТИ
# =========================
if [ -z "$PANEL_PATH" ]; then
  echo "[-] Панель не найдена в стандартных путях."
  echo "👉 Введите путь к панели или нажмите ENTER чтобы пропустить обновление панели:"
  read -rp "Путь к панели: " PANEL_PATH
fi

# =========================
# ПРОПУСК ПАНЕЛИ
# =========================
if [ -z "$PANEL_PATH" ]; then
  echo "[!] Обновление панели пропущено. Переходим к Wings..."
  UPDATE_PANEL=false
fi

# проверка пути
if [ "$UPDATE_PANEL" = true ]; then
  if [ ! -f "$PANEL_PATH/artisan" ]; then
    echo "[!] Неверный путь панели — artisan не найден"
    echo "[!] Панель будет пропущена"
    UPDATE_PANEL=false
  fi
fi

# =========================
# ОБНОВЛЕНИЕ ПАНЕЛИ
# =========================
if [ "$UPDATE_PANEL" = true ]; then

  echo "[2/8] Обновление панели..."

  cd "$PANEL_PATH"

  echo "[*] Включаем maintenance mode..."
  php artisan down || true

  # =========================
  # GIT ИЛИ RELEASE
  # =========================
  if [ -d ".git" ]; then
    echo "[*] Найден .git — обновление через git"

    git fetch --all
    git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)

  else
    echo "[*] .git не найден — используем release archive"

    echo "[*] Скачивание панели..."
    curl -L -o panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz

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
  echo "[*] Установка зависимостей..."
  composer install --no-dev --optimize-autoloader

  # =========================
  # МИГРАЦИИ
  # =========================
  echo "[*] Выполняем миграции..."
  php artisan migrate --force

  # =========================
  # КЕШ
  # =========================
  echo "[*] Очистка кеша..."
  php artisan cache:clear
  php artisan config:clear
  php artisan route:clear
  php artisan view:clear
  php artisan optimize:clear || true

  # =========================
  # QUEUE
  # =========================
  echo "[*] Перезапуск очередей..."
  php artisan queue:restart || true

  echo "[*] Выключаем maintenance mode..."
  php artisan up || true

  echo "[+] Панель обновлена"
else
  echo "[2/8] Панель пропущена"
fi

# =========================
# WINGS
# =========================
echo "[3/8] Обновление Wings..."

if systemctl list-units --type=service | grep -q wings; then
  echo "[*] Перезапуск Wings через systemd..."
  systemctl restart wings || true
  systemctl status wings --no-pager || true
else
  echo "[!] Wings service не найден"
  echo "    Если используешь Docker — перезапусти контейнер вручную"
fi

echo "======================================"
echo "   ОБНОВЛЕНИЕ ЗАВЕРШЕНО"
echo "======================================"

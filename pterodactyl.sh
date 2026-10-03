#!/bin/bash
set -uo pipefail

# ProjectBW Pterodactyl installer/updater
# Modes: install, update, both, panel, wings, install-panel,
#        update-panel, install-wings, update-wings
#
# Custom paths:
#   -panel=/path/to/pterodactyl
#   -wings=/path/to/wings
#
# Examples:
#   ./pterodactyl.sh
#   ./pterodactyl.sh update
#   ./pterodactyl.sh update-panel -panel=/hdd/pterodactyl
#   ./pterodactyl.sh update-wings -wings=/hdd/pterodactyl/wings

[[ $EUID -eq 0 ]] || { echo "[!] Запустите от root."; exit 1; }

MODE=""
PANEL_PATH=""
WINGS_PATH=""
WINGS_EXPLICIT=false
LOGS=false
PANEL_RESULT=0
WINGS_RESULT=0

DEFAULT_PANEL_PATH="/var/www/pterodactyl"
DEFAULT_WINGS_PATH="/usr/local/bin/wings"
PANEL_USER="www-data"
PANEL_GROUP="www-data"

info(){ echo "[*] $*"; }
ok(){ echo "[+] $*"; }
warn(){ echo "[!] $*"; }
err(){ echo "[-] $*" >&2; }

usage(){
cat <<EOF
ProjectBW Pterodactyl

$0                         интерактивное меню
$0 install                 установить Panel + Wings
$0 update                  обновить Panel + Wings
$0 both                    обновить Panel + Wings
$0 panel                   обновить Panel
$0 wings                   обновить Wings
$0 install-panel           установить Panel
$0 update-panel            обновить Panel
$0 install-wings           установить Wings
$0 update-wings            обновить Wings

Кастомные пути:
  -panel=/path             путь Panel
  -wings=/path              путь бинарника Wings
  -wings=default             стандартный путь Wings: /usr/local/bin/wings
  -update                    обновить Panel + Wings
  -logs                      подробный лог выполнения команд

Примеры:
  $0 update -panel=/hdd/pterodactyl
  $0 update-panel -panel=/hdd/pterodactyl
  $0 update-wings -wings=/hdd/pterodactyl/wings
  $0 -panel=/hdd/pterodactyl -wings=default -update
  $0 -panel=/hdd/pterodactyl -wings=default -update -logs
  $0 update -panel=/hdd/pterodactyl -wings=/hdd/pterodactyl/wings
EOF
}

for arg in "$@"; do
  case "$arg" in
    install|update|both|panel|wings|install-panel|update-panel|install-wings|update-wings)
      [[ -z "$MODE" ]] || { err "Указано несколько режимов."; exit 1; }
      MODE="$arg" ;;
    -update)
      [[ -z "$MODE" ]] || { err "Указано несколько режимов."; exit 1; }
      MODE="update" ;;
    -logs)
      LOGS=true ;;
    -panel=*) PANEL_PATH="${arg#*=}" ;;
    -wings=*)
      WINGS_PATH="${arg#*=}"
      WINGS_EXPLICIT=true
      [[ "$WINGS_PATH" == "default" ]] && WINGS_PATH="$DEFAULT_WINGS_PATH" ;;
    -h|--help|help) usage; exit 0 ;;
    *) err "Неизвестный аргумент: $arg"; usage; exit 1 ;;
  esac
done

[[ "$MODE" == "update" || "$MODE" == "both" || "$MODE" == "panel" || "$MODE" == "wings" || "$MODE" == "update-panel" || "$MODE" == "update-wings" ]] && LOGS=true

[[ -n "$MODE" ]] || {
  echo "======================================"
  echo " ProjectBW Pterodactyl"
  echo "======================================"
  echo "1) Установить Panel + Wings"
  echo "2) Обновить Panel + Wings"
  echo "3) Установить Panel"
  echo "4) Обновить Panel"
  echo "5) Установить Wings"
  echo "6) Обновить Wings"
  echo "7) Выйти"
  echo
  read -rp "Выберите [1-7]: " choice
  case "$choice" in
    1) MODE=install ;; 2) MODE=update ;;
    3) MODE=install-panel ;; 4) MODE=update-panel ;;
    5) MODE=install-wings ;; 6) MODE=update-wings ;;
    7) exit 0 ;;
    *) err "Неверный выбор."; exit 1 ;;
  esac
}

if [[ "$LOGS" == true ]]; then
  export PS4='[LOG] + '
  set -x
fi

case "$MODE" in
  both) MODE=update ;;
  panel) MODE=update-panel ;;
  wings) MODE=update-wings ;;
esac

detect_panel(){
  [[ -n "$PANEL_PATH" ]] && return
  local p
  for p in /var/www/pterodactyl /srv/pterodactyl /opt/pterodactyl /hdd/pterodactyl; do
    if [[ -f "$p/artisan" ]]; then PANEL_PATH="$p"; info "Panel: $PANEL_PATH"; return; fi
  done
  PANEL_PATH="$DEFAULT_PANEL_PATH"
}

detect_wings(){
  [[ "$WINGS_EXPLICIT" == true ]] && return
  [[ -n "$WINGS_PATH" ]] && return
  local p
  if systemctl cat wings >/dev/null 2>&1; then
    p="$(systemctl cat wings 2>/dev/null | sed -n 's/^[[:space:]]*ExecStart=\([^[:space:]]*wings\).*/\1/p' | head -n1)"
    if [[ -n "$p" ]]; then WINGS_PATH="$p"; info "Wings из systemd: $WINGS_PATH"; return; fi
  fi
  [[ -x /usr/local/bin/wings ]] && WINGS_PATH=/usr/local/bin/wings || WINGS_PATH="$DEFAULT_WINGS_PATH"
}

panel_permissions(){
  local p="$1"
  if id "$PANEL_USER" >/dev/null 2>&1; then
    chown -R "$PANEL_USER:$PANEL_GROUP" "$p"
  else
    warn "Пользователь $PANEL_USER не найден; chown пропущен."
  fi
  chmod -R 755 "$p/storage" "$p/bootstrap/cache" 2>/dev/null || true
}

install_panel(){
  local p="$1"
  info "Установка Panel в $p"

  if [[ -f "$p/artisan" ]]; then
    err "Panel уже существует: $p"
    return 1
  fi
  if [[ -d "$p" && -n "$(find "$p" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    err "Каталог $p уже существует и не пуст."
    return 1
  fi

  mkdir -p "$p" || return 1
  cd "$p" || return 1

  curl -fL --retry 3 --connect-timeout 15     -o panel.tar.gz     https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz || return 1
  tar -xzf panel.tar.gz || return 1
  rm -f panel.tar.gz

  chmod -R 755 storage bootstrap/cache 2>/dev/null || true
  [[ -f .env ]] || cp .env.example .env

  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader || return 1

  if ! grep -q '^APP_KEY=.' .env 2>/dev/null; then
    php artisan key:generate --force || return 1
    warn "Сохраните APP_KEY из $p/.env в безопасном месте."
  fi

  panel_permissions "$p"

  echo
  warn "Файлы Panel установлены. Завершите первоначальную настройку:"
  echo "  cd $p"
  echo "  php artisan p:environment:setup"
  echo "  php artisan p:environment:database"
  echo "  php artisan p:environment:mail"
  echo "  php artisan migrate --seed --force"
  echo "  php artisan p:user:make"
  echo
  warn "Cron и pteroq.service настройте по официальной документации Pterodactyl."
  ok "Panel установлена: $p"
  return 0
}

update_panel(){
  local p="$1"
  local maintenance=false

  [[ -f "$p/artisan" ]] || { err "artisan не найден: $p"; return 1; }
  cd "$p" || return 1

  info "Обновление Panel: $p"

  # .env must survive replacement of release files.
  [[ -f .env ]] && cp -a .env .env.projectbw-backup

  if php artisan down; then maintenance=true; fi

  info "Скачивание последнего релиза Panel..."
  if ! curl -fL --retry 3 --connect-timeout 15       https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz       | tar -xz; then
    err "Не удалось скачать/распаковать Panel."
    [[ -f .env.projectbw-backup ]] && mv -f .env.projectbw-backup .env
    [[ "$maintenance" == true ]] && php artisan up || true
    return 1
  fi

  [[ -f .env.projectbw-backup ]] && mv -f .env.projectbw-backup .env

  chmod -R 755 storage bootstrap/cache 2>/dev/null || true

  info "Composer..."
  if ! COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader; then
    err "Composer завершился с ошибкой."
    php artisan up || true
    return 1
  fi

  info "Миграции..."
  if ! php artisan migrate --seed --force; then
    err "Миграции завершились с ошибкой."
    php artisan up || true
    return 1
  fi

  php artisan view:clear || true
  php artisan config:clear || true
  php artisan route:clear || true
  php artisan cache:clear || true
  php artisan optimize:clear || true

  panel_permissions "$p"
  php artisan queue:restart || true

  if systemctl list-unit-files 2>/dev/null | grep -q '^pteroq\.service'; then
    systemctl restart pteroq.service || warn "Не удалось перезапустить pteroq.service"
  fi

  php artisan up || true
  ok "Panel обновлена: $p"
  return 0
}

wings_arch(){
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) err "Неподдерживаемая архитектура: $(uname -m)"; return 1 ;;
  esac
}

install_wings(){
  local w="$1" arch
  arch="$(wings_arch)" || return 1

  info "Установка Wings: $w"
  mkdir -p /etc/pterodactyl "$(dirname "$w")"

  [[ -f "$w" ]] && { err "Wings уже существует: $w"; return 1; }

  curl -fL --retry 3 --connect-timeout 15     -o "$w"     "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$arch" || return 1
  chmod u+x "$w"

  if [[ ! -f /etc/systemd/system/wings.service ]]; then
    cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=$w
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable wings
  else
    info "Существующий wings.service не изменяем."
  fi

  if [[ ! -f /etc/pterodactyl/config.yml ]]; then
    warn "Нет /etc/pterodactyl/config.yml."
    warn "Создайте Node в Panel и установите config.yml."
    warn "Wings установлен, но запуск отложен до появления config.yml."
  else
    systemctl restart wings || {
      err "Wings не запустился. Проверьте: journalctl -u wings -n 100 --no-pager"
      return 1
    }
    systemctl status wings --no-pager || true
  fi
  ok "Wings установлен: $w"
  return 0
}

update_wings(){
  local w="$1" arch backup
  arch="$(wings_arch)" || return 1

  [[ -f "$w" ]] || {
    err "Wings не найден: $w"
    err "Для первой установки используйте install-wings."
    return 1
  }

  info "Обновление Wings: $w"

  if systemctl is-active --quiet wings; then
    systemctl stop wings || return 1
  fi

  backup="$w.projectbw-backup"
  cp -a "$w" "$backup"

  info "Скачивание последнего Wings ($arch)..."
  if ! curl -fL --retry 3 --connect-timeout 15       -o "$w"       "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$arch"; then
    mv -f "$backup" "$w"
    systemctl start wings || true
    return 1
  fi

  chmod u+x "$w"

  systemctl daemon-reload
  if ! systemctl restart wings; then
    err "Wings не запустился после обновления."
    warn "Старый бинарник сохранён: $backup"
    systemctl status wings --no-pager || true
    return 1
  fi

  rm -f "$backup"
  systemctl status wings --no-pager || true
  ok "Wings обновлён: $w"
  return 0
}

run_panel(){
  detect_panel
  case "$1" in
    install) install_panel "$PANEL_PATH"; PANEL_RESULT=$? ;;
    update) update_panel "$PANEL_PATH"; PANEL_RESULT=$? ;;
  esac
}

run_wings(){
  detect_wings
  case "$1" in
    install) install_wings "$WINGS_PATH"; WINGS_RESULT=$? ;;
    update) update_wings "$WINGS_PATH"; WINGS_RESULT=$? ;;
  esac
}

case "$MODE" in
  install)
    run_panel install
    run_wings install
    ;;
  update)
    # Independent execution: if Panel fails, Wings is still updated.
    run_panel update
    run_wings update
    ;;
  install-panel)
    run_panel install
    ;;
  update-panel)
    run_panel update
    ;;
  install-wings)
    run_wings install
    ;;
  update-wings)
    run_wings update
    ;;
  *)
    usage
    exit 1
    ;;
esac

echo
echo "======================================"
echo " RESULT"
echo "======================================"

if [[ "$MODE" == "install" || "$MODE" == "update" ]]; then
  [[ "$PANEL_RESULT" -eq 0 ]] && ok "Panel: OK" || err "Panel: FAILED"
  [[ "$WINGS_RESULT" -eq 0 ]] && ok "Wings: OK" || err "Wings: FAILED"
  [[ "$PANEL_RESULT" -eq 0 && "$WINGS_RESULT" -eq 0 ]]
else
  case "$MODE" in
    install-panel|update-panel) [[ "$PANEL_RESULT" -eq 0 ]] ;;
    install-wings|update-wings) [[ "$WINGS_RESULT" -eq 0 ]] ;;
  esac
fi

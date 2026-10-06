# vdsbw
vdsbw


bash <(curl -fsSL https://raw.githubusercontent.com/bwproject/vdsbw/main/install.sh)

bash <(curl -fsSL https://raw.githubusercontent.com/bwproject/vdsbw/main/portainer.sh)

bash <(curl -fsSL https://raw.githubusercontent.com/bwproject/vdsbw/main/mtproto.sh)


bash <(curl -fsSL https://raw.githubusercontent.com/bwproject/vdsbw/main/teleproxy.sh)

bash <(curl -fsSL https://raw.githubusercontent.com/bwproject/vdsbw/main/pterodactyl.sh)

bash <(curl -fsSL https://raw.githubusercontent.com/bwproject/vdsbw/main/pterodactyl.sh) \
-panel=/hdd/pterodactyl/volumes/f1972106-319b-4063-a001-3fbd0f10f66c/webroot/pterodactyl

bash <(curl -fsSL https://raw.githubusercontent.com/bwproject/vdsbw/main/pterodactyl.sh) \
-panel=/hdd/pterodactyl/volumes/f1972106-319b-4063-a001-3fbd0f10f66c/webroot/pterodactyl \
-wings=default \
-update \
-logs

bash <(curl -fsSL https://raw.githubusercontent.com/bwproject/vdsbw/main/tg-zapret.sh)

## removeold.sh — автоматическая очистка Debian

Скрипт автоматически очищает сервер от старого системного мусора, APT-кэша, старых логов, Docker-мусора и временных файлов.

Установка и первый запуск:

```bash
wget -O /tmp/removeold.sh https://raw.githubusercontent.com/bwproject/vdsbw/main/removeold.sh && chmod +x /tmp/removeold.sh && sudo /tmp/removeold.sh
```

После установки скрипт:

- устанавливает `screen`, если его нет;
- создаёт screen-сессию `remove` для выполнения очистки и вывода логов;
- автоматически проверяет обновления скрипта с GitHub;
- запускает очистку каждые 5 дней в 03:22;
- очищает APT-кэш и неиспользуемые пакеты;
- очищает старые systemd journal и системные логи;
- очищает временные файлы;
- очищает неиспользуемые Docker-контейнеры, образы, сети и build cache;
- ограничивает слишком большие Docker-логи;
- после Docker-очистки перезапускает контейнеры, которые работали до очистки;
- перезапускает Pterodactyl Wings и Nginx, если соответствующие сервисы установлены.

### Просмотр работы removeold

Подключиться к текущей screen-сессии:

```bash
screen -r remove
```

Выйти из screen без остановки процесса: **Ctrl+A**, затем **D**.

Список screen-сессий:

```bash
screen -ls
```

Постоянный лог работы:

```bash
tail -f /var/log/removeold.log
```

Проверить таймер systemd:

```bash
systemctl list-timers removeold.timer
```

Ручной запуск очистки:

```bash
sudo /usr/local/sbin/removeold.sh --run
```

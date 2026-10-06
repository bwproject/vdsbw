#!/usr/bin/env bash
set -u
set -o pipefail

INSTALL_PATH="/usr/local/sbin/removeold.sh"
SERVICE_NAME="removeold.service"
TIMER_NAME="removeold.timer"
REPO_RAW_URL="https://raw.githubusercontent.com/bwproject/vdsbw/main/removeold.sh"
STATE_DIR="/var/lib/removeold"
LOG_FILE="/var/log/removeold.log"
LOCK_FILE="/run/removeold.lock"
DOCKER_LOG_MAX_BYTES=$((200 * 1024 * 1024))
SCREEN_NAME="remove"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

run_cmd() {
    local description="$1"
    shift
    log "$description"
    if "$@" >>"$LOG_FILE" 2>&1; then
        log "OK: $description"
    else
        log "WARNING: failed: $description"
    fi
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] || { echo "Run as root: sudo bash removeold.sh"; exit 1; }
}

ensure_screen() {
    command -v screen >/dev/null 2>&1 || {
        log "screen is not installed. Installing screen..."
        apt-get update
        apt-get install -y screen
    }

    if screen -list 2>/dev/null | grep -qE "[[:space:]]+[0-9]+\\.${SCREEN_NAME}[[:space:]]"; then
        return 0
    fi

    log "screen session ${SCREEN_NAME} not found. Creating it..."
    screen -dmS "$SCREEN_NAME" bash -c "exec \"$INSTALL_PATH\" --run"
    sleep 1

    if screen -list 2>/dev/null | grep -qE "[[:space:]]+[0-9]+\\.${SCREEN_NAME}[[:space:]]"; then
        log "screen session ${SCREEN_NAME} started."
        log "Attach with: screen -r ${SCREEN_NAME}"
    else
        log "WARNING: failed to create screen session ${SCREEN_NAME}."
    fi
}

install_self() {
    mkdir -p "$STATE_DIR"
    touch "$LOG_FILE"
    chmod 700 "$STATE_DIR"
    chmod 600 "$LOG_FILE"
    if [[ ! -f "$INSTALL_PATH" ]] || ! cmp -s "$0" "$INSTALL_PATH"; then
        install -m 0755 "$0" "$INSTALL_PATH"
    fi
}

update_self() {
    command -v curl >/dev/null 2>&1 || return 0
    local tmp
    tmp="$(mktemp "$STATE_DIR/removeold.XXXXXX")"

    log "Checking removeold.sh for updates..."
    if ! curl -fsSL --connect-timeout 10 --max-time 60 "$REPO_RAW_URL" -o "$tmp"; then
        rm -f "$tmp"
        log "WARNING: GitHub update check failed."
        return 0
    fi

    if ! head -n1 "$tmp" | grep -qE '^#!.*/(ba)?sh$'; then
        rm -f "$tmp"
        log "WARNING: downloaded update is not a shell script."
        return 0
    fi

    chmod 0755 "$tmp"
    if [[ ! -f "$INSTALL_PATH" ]] || ! cmp -s "$tmp" "$INSTALL_PATH"; then
        install -m 0755 "$tmp" "$INSTALL_PATH"
        rm -f "$tmp"
        log "Updated removeold.sh. Restarting with new version..."
        exec "$INSTALL_PATH" --run
    fi
    rm -f "$tmp"
    log "removeold.sh is up to date."
}

install_systemd() {
    cat > "/etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=ProjectBW automatic Debian disk cleanup
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_PATH --run
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

    cat > "/etc/systemd/system/$TIMER_NAME" <<EOF
[Unit]
Description=ProjectBW disk cleanup every 5 days

[Timer]
OnBootSec=30min
OnUnitActiveSec=5d
Persistent=true
RandomizedDelaySec=30min
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$TIMER_NAME"
    log "Installed $TIMER_NAME: cleanup every 5 days."
}

cleanup_apt() {
    command -v apt-get >/dev/null 2>&1 || return 0

    run_cmd "Cleaning APT package cache" apt-get clean
    run_cmd "Removing obsolete APT packages from cache" apt-get autoclean -y
    run_cmd "Removing unused APT packages" apt-get autoremove -y

    if [[ -d /var/cache/apt/archives ]]; then
        log "Removing leftover downloaded .deb packages..."
        find /var/cache/apt/archives -type f -name '*.deb' -delete 2>>"$LOG_FILE" || true
        find /var/cache/apt/archives -type f -name '*.bin' -delete 2>>"$LOG_FILE" || true
    fi

    if [[ -d /var/lib/apt/lists ]]; then
        log "Removing cached APT repository lists..."
        find /var/lib/apt/lists -type f -delete 2>>"$LOG_FILE" || true
        find /var/lib/apt/lists -type d -empty -delete 2>>"$LOG_FILE" || true
    fi
}

cleanup_journal() {
    command -v journalctl >/dev/null 2>&1 || return 0
    run_cmd "Vacuuming journal older than 14 days" journalctl --vacuum-time=14d
    run_cmd "Limiting journal to 500 MB" journalctl --vacuum-size=500M
}

cleanup_logs() {
    log "Cleaning old rotated logs..."
    find /var/log -type f \( -name '*.gz' -o -name '*.xz' -o -name '*.bz2' -o -name '*.old' \) -mtime +30 -print -delete >>"$LOG_FILE" 2>&1 || true
    find /var/log -type f \( -name 'syslog.*' -o -name 'messages.*' -o -name 'auth.log.*' -o -name 'kern.log.*' -o -name 'daemon.log.*' \) -mtime +14 -delete 2>>"$LOG_FILE" || true

    if [[ -d /var/log/nginx ]]; then
        log "Cleaning old Nginx logs..."
        find /var/log/nginx -type f \( -name '*.gz' -o -name '*.xz' -o -name '*.bz2' -o -name '*.old' \) -mtime +7 -print -delete >>"$LOG_FILE" 2>&1 || true
        find /var/log/nginx -type f -name '*.log.*' -mtime +14 -print -delete >>"$LOG_FILE" 2>&1 || true
        find /var/log/nginx -type f -name '*.log' -size +200M -print -exec truncate -s 0 {} \; >>"$LOG_FILE" 2>&1 || true
    fi

    [[ -d /var/crash ]] && find /var/crash -type f -mtime +30 -delete 2>>"$LOG_FILE" || true
    find /tmp -xdev -type f -mtime +7 -delete 2>>"$LOG_FILE" || true
    find /var/tmp -xdev -type f -mtime +14 -delete 2>>"$LOG_FILE" || true
}

cleanup_docker() {
    command -v docker >/dev/null 2>&1 || { log "Docker not installed; skipping."; return 0; }
    docker info >/dev/null 2>&1 || { log "Docker not running; skipping."; return 0; }

    local running_containers=""
    running_containers="$(docker ps -q 2>/dev/null || true)"
    if [[ -n "$running_containers" ]]; then
        log "Remembering running Docker containers before cleanup: $(wc -w <<< "$running_containers")"
    fi

    run_cmd "Removing stopped Docker containers" docker container prune -f
    run_cmd "Removing unused Docker images" docker image prune -af
    run_cmd "Removing unused Docker networks" docker network prune -f
    run_cmd "Removing Docker build cache" docker builder prune -af

    local count=0 logfile size
    while IFS= read -r -d '' logfile; do
        size="$(stat -c '%s' "$logfile" 2>/dev/null || echo 0)"
        if [[ "$size" =~ ^[0-9]+$ ]] && (( size > DOCKER_LOG_MAX_BYTES )); then
            log "Truncating Docker log: $logfile"
            truncate -s 0 "$logfile" 2>>"$LOG_FILE" && count=$((count + 1))
        fi
    done < <(find /var/lib/docker/containers -type f -name '*-json.log' -print0 2>/dev/null)
    log "Oversized Docker logs truncated: $count"

    if [[ -n "$running_containers" ]]; then
        log "Restarting Docker containers that were running before cleanup..."
        while IFS= read -r container_id; do
            [[ -n "$container_id" ]] || continue
            if docker restart "$container_id" >>"$LOG_FILE" 2>&1; then
                log "OK: restarted Docker container $container_id"
            else
                log "WARNING: failed to restart Docker container $container_id"
            fi
        done <<< "$running_containers"
    fi
}

cleanup_docker_tmp() {
    [[ -d /var/lib/docker ]] || return 0
    find /var/lib/docker -xdev -type f -name '*.tmp' -mtime +7 -delete 2>>"$LOG_FILE" || true
}

cleanup() {
    exec 9>"$LOCK_FILE"
    flock -n 9 || { log "Another cleanup is already running."; exit 0; }

    log "===== ProjectBW cleanup started ====="
    local before after freed
    before="$(df -B1 --output=avail / | tail -n1 | tr -d ' ')"

    cleanup_apt
    cleanup_journal
    cleanup_logs
    cleanup_docker
    cleanup_docker_tmp

    if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^wings.service'; then
        run_cmd "Restarting Pterodactyl Wings" systemctl restart wings
    elif systemctl list-unit-files --type=service 2>/dev/null | grep -q '^pterodactyl-wings.service'; then
        run_cmd "Restarting Pterodactyl Wings" systemctl restart pterodactyl-wings
    else
        log "Wings service not found; skipping."
    fi

    if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^nginx.service'; then
        run_cmd "Restarting Nginx" systemctl restart nginx
    else
        log "Nginx service not found; skipping."
    fi

    after="$(df -B1 --output=avail / | tail -n1 | tr -d ' ')"
    if [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ ]]; then
        freed=$((after - before))
        (( freed >= 0 )) && log "Freed: $(numfmt --to=iec "$freed" 2>/dev/null || echo "$freed bytes")"
    fi

    df -h / | tee -a "$LOG_FILE"
    date +%s > "$STATE_DIR/last_run"
    log "===== ProjectBW cleanup finished ====="
}

main() {
    require_root

    install_self
    ensure_screen

    if [[ -z "${STY:-}" ]]; then
        if screen -list 2>/dev/null | grep -qE "[[:space:]]+[0-9]+\\.${SCREEN_NAME}[[:space:]]"; then
            log "Cleanup is running in screen session ${SCREEN_NAME}."
            exit 0
        fi
        log "WARNING: screen session could not be started; continuing without screen."
    fi

    if [[ "${1:-}" != "--run" ]]; then
        install_systemd
    fi

    update_self
    cleanup
}

main "$@"

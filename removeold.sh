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
    run_cmd "Cleaning APT cache" apt-get clean
    run_cmd "Removing unused APT packages" apt-get autoremove -y
    log "Removing old APT package lists..."
    find /var/lib/apt/lists -type f -delete 2>>"$LOG_FILE" || true
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
    [[ -d /var/crash ]] && find /var/crash -type f -mtime +30 -delete 2>>"$LOG_FILE" || true
    find /tmp -xdev -type f -mtime +7 -delete 2>>"$LOG_FILE" || true
    find /var/tmp -xdev -type f -mtime +14 -delete 2>>"$LOG_FILE" || true
}

cleanup_docker() {
    command -v docker >/dev/null 2>&1 || { log "Docker not installed; skipping."; return 0; }
    docker info >/dev/null 2>&1 || { log "Docker not running; skipping."; return 0; }

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

    if [[ "${1:-}" != "--run" ]]; then
        install_self
        install_systemd
        update_self
        cleanup
    else
        update_self
        cleanup
    fi
}

main "$@"

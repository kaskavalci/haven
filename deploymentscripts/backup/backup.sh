#!/bin/sh
# Haven backup: tarball data -> local path, upload to Google Drive, retain last 7.
# On failure or corruption, notify via Home Assistant webhook.
# Requires: BACKUP_SOURCE_PATH, BACKUP_LOCAL_PATH; optional: NOTIFY_WEBHOOK_URL, RCLONE_*.

set -u

# Cron on Alpine often runs jobs with a minimal environment and won't include
# Compose-provided env vars. When available, import selected variables from PID 1.
if [ -r /proc/1/environ ]; then
    _tmp="/tmp/pid1-environ.$$"
    tr '\0' '\n' < /proc/1/environ > "$_tmp" 2>/dev/null || true
    while IFS= read -r kv; do
        case "$kv" in
            BACKUP_SOURCE_PATH=*|BACKUP_LOCAL_PATH=*|NOTIFY_WEBHOOK_URL=*|RCLONE_REMOTE=*|RCLONE_REMOTE_PATH=*)
                export "$kv"
                ;;
        esac
    done < "$_tmp"
    rm -f "$_tmp"
fi

# Defaults (kept in sync with Dockerfile ENV)
BACKUP_SOURCE_PATH="${BACKUP_SOURCE_PATH:-/data}"
BACKUP_LOCAL_PATH="${BACKUP_LOCAL_PATH:-/backups}"

notify() {
    _msg="$1"
    [ -z "${NOTIFY_WEBHOOK_URL:-}" ] && return 0
    _json_msg="$(printf '%s' "$_msg" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    wget -q -O /dev/null \
        --post-data="{\"title\":\"Haven Backup\",\"message\":\"$_json_msg\",\"source\":\"haven-backup\"}" \
        --header="Content-Type: application/json" \
        "$NOTIFY_WEBHOOK_URL" 2>/dev/null || true
}

fail() {
    notify "$1"
    echo "$1" >&2
    exit 1
}

TIMESTAMP="$(date +%Y%m%d-%H%M)"
ARCHIVE="${BACKUP_LOCAL_PATH}/haven-${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_LOCAL_PATH"
[ -d "$BACKUP_SOURCE_PATH" ] || fail "Backup source directory does not exist: $BACKUP_SOURCE_PATH"

# 1. Create tarball
if ! tar czf "$ARCHIVE" -C "$BACKUP_SOURCE_PATH" . ; then
    fail "Backup failed: tar failed"
fi

# 2. Corruption checks: must exist and non-zero size
[ -f "$ARCHIVE" ] || fail "Backup failed: archive not created"
SZ="$(wc -c < "$ARCHIVE")"
[ "$SZ" -gt 0 ] || fail "Backup failed: empty archive"

# If a previous backup exists, new one must not be significantly smaller (heuristic for corruption/missing data).
# Allow up to 1% shrink to avoid false positives from minor SQLite/tar variance.
PREV="$(ls -t "$BACKUP_LOCAL_PATH"/haven-*.tar.gz 2>/dev/null | sed -n '2p')"
if [ -n "$PREV" ] && [ -f "$PREV" ]; then
    PREVSZ="$(wc -c < "$PREV")"
    MIN_OK=$((PREVSZ - PREVSZ / 100))
    [ "$SZ" -ge "$MIN_OK" ] || fail "Backup corrupt: new backup significantly smaller than previous ($SZ < $PREVSZ, allowed min $MIN_OK)"
fi

# 3. Upload to Google Drive (optional if rclone not configured)
if [ -n "${RCLONE_REMOTE:-}" ] && [ -n "${RCLONE_REMOTE_PATH:-}" ]; then
    if ! rclone copy "$ARCHIVE" "${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH}/" ; then
        fail "Backup failed: rclone upload failed"
    fi
fi

# 4. Retention: keep last 7 backups
ls -t "$BACKUP_LOCAL_PATH"/haven-*.tar.gz 2>/dev/null | tail -n +8 | while read -r f; do
    rm -f "$f"
done

echo "Backup completed: $ARCHIVE"

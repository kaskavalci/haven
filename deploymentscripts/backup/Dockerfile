# Backup sidecar for Haven: tarballs data, uploads to Google Drive via rclone,
# keeps last 7 backups, notifies on failure via Home Assistant webhook.
FROM alpine:3.19

RUN apk add --no-cache \
    cronie \
    tar \
    gzip \
    wget \
    ca-certificates \
    rclone

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

COPY crontab /etc/crontabs/root
RUN chmod 0600 /etc/crontabs/root

# Defaults; override via env in compose
ENV BACKUP_SOURCE_PATH=/data \
    BACKUP_LOCAL_PATH=/backups

WORKDIR /data

CMD ["crond", "-f"]

# Portainer deployment: SQLite, bind mount, and backups

**Date:** 2026-03-01
**Author:** Cursor

## Overview

This setup runs Haven with SQLite (no PostgreSQL), stores data on a host bind mount, and adds a sidecar container that periodically backs up the data (database + Active Storage files) to a local directory and optionally to Google Drive. Failed or corrupt backups trigger a Home Assistant webhook notification.

## Prerequisites

- Portainer (or any Docker Compose–capable host)
- Host path for Haven data: `/mnt/ssd/nfs/docker_data/haven` (or adjust paths in the stack)
- NFS share for backups: `192.168.0.238:/export/alpha/backup/docker` (must be reachable from the host; options: `rw,nolock,soft`)
- Optional: Google Cloud service account for Google Drive uploads (rclone)
- Optional: Home Assistant webhook URL for alerts

## 1. Bind mount (data location)

Haven data (SQLite DB and uploaded images) lives under a single directory. The stack uses a bind mount so that directory is on the host:

- **Path:** `/mnt/ssd/nfs/docker_data/haven` → `/app/storage` in the Haven container
- Create the directory on the host before first deploy:
  ```bash
  sudo mkdir -p /mnt/ssd/nfs/docker_data/haven
  sudo chown 1000:1000 /mnt/ssd/nfs/docker_data/haven   # or the UID your Haven process runs as
  ```

If you already had data in a Docker named volume, copy it into this path once, then switch the stack to this compose file.

## 2. Stack file and deploy

Use the root-level stack file:

- **File:** `docker-compose.portainer.yml`

Deploy from the repo root so the backup image can be built (context: `deploymentscripts/backup`). In Portainer: create a new stack, paste the contents of `docker-compose.portainer.yml` (or point at the file in your repo), set the environment variables below, then deploy.

## 3. Environment variables

### Haven service

| Variable | Description |
|----------|-------------|
| `HAVEN_USER_EMAIL` | Admin/login email. |
| `HAVEN_USER_PASS` | Admin/login password. |

### Backup service

| Variable | Description |
|----------|-------------|
| `NOTIFY_WEBHOOK_URL` | Home Assistant webhook URL. On backup failure or corruption, a JSON payload is POSTed with `title`, `message`, and `source`. Omit to disable notifications. |
| `RCLONE_REMOTE` | Rclone remote name (e.g. `gdrive`) for Google Drive upload. Leave unset to skip cloud upload. |
| `RCLONE_REMOTE_PATH` | Path on the remote (e.g. `haven_backups`). Used with `RCLONE_REMOTE`. |

Backup tarballs are always written to the **NFS volume** defined in the stack (`192.168.0.238:/export/alpha/backup/docker`, mounted at `/backups` in the container). No extra env or host path is required.

## 4. Google Drive (rclone)

To upload backups to Google Drive, configure rclone inside the backup container using a **service account** (recommended for unattended cron).

1. **Google Cloud:** Create a project, enable the Google Drive API, create a service account, and download its JSON key file.
2. **Drive:** Create a folder for backups and share it with the service account email (Editor).
3. **Rclone config:** Either:
   - **Option A:** Build a `rclone.conf` that uses the service account (e.g. `rclone config create gdrive drive service_account_file /path/to/key.json`), then mount it into the container at `/root/.config/rclone/rclone.conf`.
   - **Option B:** Mount the JSON key into the container and use rclone environment variables (see [rclone documentation](https://rclone.org/drive/#config-is-in-environment-variables)) to point at the key and set the remote name.

4. Set `RCLONE_REMOTE` and `RCLONE_REMOTE_PATH` in the stack environment (e.g. `gdrive` and `haven_backups`). The path in `RCLONE_REMOTE_PATH` must be an **existing folder** on Google Drive (create it in the Drive UI or via rclone before the first backup).

If `RCLONE_REMOTE` or `RCLONE_REMOTE_PATH` is empty, the backup script skips the upload step; local tarballs are still created and retained.

### Using rclone config from another machine

If you already have rclone configured on another machine (e.g. with `rclone config`), you can copy that config to the host running Portainer and mount it into the backup container.

1. **Copy the config file from the other machine**

   rclone stores its config in:
   - **Linux/macOS:** `~/.config/rclone/rclone.conf`
   - **Windows:** `%APPDATA%\rclone\rclone.conf`

   On the **other machine**, copy the file to your Portainer host (e.g. via `scp`):

   ```bash
   # From your laptop or the other machine (replace user@portainer-host with your host)
   scp ~/.config/rclone/rclone.conf user@portainer-host:/mnt/ssd/nfs/docker_data/haven/rclone/rclone.conf
   ```

   Create the directory on the **Portainer host** first:

   ```bash
   mkdir -p /mnt/ssd/nfs/docker_data/haven/rclone
   ```

2. **If the config references a service account key (or other file)**

   If your remote uses `service_account_file = /some/path/to/key.json`, you must also copy that JSON to the host and mount it into the container at **the same path** that appears in the config. The container runs as root and reads config from `/root/.config/rclone/rclone.conf`, so use a path inside the container for the key (e.g. `/root/gdrive-sa.json`).

   - Copy the key to the host:
     ```bash
     scp /path/on/other/machine/key.json user@portainer-host:/mnt/ssd/nfs/docker_data/haven/rclone/gdrive-sa.json
     ```
   - Edit `rclone.conf` on the host so the remote uses a path that will exist in the container. For example, if the config has:
     ```ini
     [gdrive]
     type = drive
     service_account_file = /home/me/gdrive-sa.json
     ```
     change it to:
     ```ini
     [gdrive]
     type = drive
     service_account_file = /root/gdrive-sa.json
     ```
     Then we will mount the host key file to `/root/gdrive-sa.json` in the container.

3. **Mount the config (and key) in the stack**

   In `docker-compose.portainer.yml`, under `haven-backup` → `volumes`, uncomment and adjust the rclone mounts if needed. Example (paths on host under `/mnt/ssd/nfs/docker_data/haven/rclone/`):

   ```yaml
   volumes:
     - /mnt/ssd/nfs/docker_data/haven:/data:ro
     - haven_backups:/backups
     # Mount rclone config directory (not a single file) so rclone can rename/write token updates.
     - /mnt/ssd/nfs/docker_data/haven/rclone:/root/.config/rclone
   ```

4. **Set env vars and redeploy**

   In Portainer, set `RCLONE_REMOTE` to the remote name in your config (e.g. `gdrive`) and `RCLONE_REMOTE_PATH` to the folder on the remote (e.g. `haven_backups`). Redeploy the stack.

5. **Test**

   Run a one-off backup to confirm uploads work:

   ```bash
   docker exec haven-backup /usr/local/bin/backup.sh
   ```

   Check the container logs and the Google Drive folder.

**Security:** The config (and any key file) may contain secrets. Restrict permissions on the host (e.g. `chmod 600 rclone.conf gdrive-sa.json`) and keep the directory only on the host that runs the stack.

## 5. Backup behavior

- **Schedule:** Daily at 02:00 (container time). The backup container runs `crond -f` and executes `backup.sh` via cron.
- **What is backed up:** The entire Haven data directory (SQLite DB + Active Storage files) as a single tarball: `haven-YYYYMMDD-HHMM.tar.gz`.
- **Where:** Tarballs are written to `/backups` in the container, which is the NFS volume `192.168.0.238:/export/alpha/backup/docker`. The same file is uploaded to Google Drive if rclone is configured.
- **Retention:** The last **7** backups are kept locally; older files are deleted after each successful run. Google Drive retention is not applied automatically; you can add a separate cleanup or manage folders manually.
- **Corruption checks:** Before considering a run successful, the script checks that the new archive exists, has size &gt; 0, and (if a previous backup exists) is not smaller than the previous one. If any check fails, the script does not upload, does not rotate, sends a notification (if `NOTIFY_WEBHOOK_URL` is set), and exits with an error.

## 6. Home Assistant notification

When a backup fails or is considered corrupt, the script sends a POST request to `NOTIFY_WEBHOOK_URL` with:

```json
{
  "title": "Haven Backup",
  "message": "<error or corruption message>",
  "source": "haven-backup"
}
```

The `message` field is escaped for JSON. Use a Home Assistant webhook trigger (or an automation that reacts to the webhook) to notify you (e.g. push, persistent notification).

## 7. Restore from a backup

1. Stop the Haven stack (and backup container).
2. Move or rename the current data directory on the host (e.g. `mv /mnt/ssd/nfs/docker_data/haven /mnt/ssd/nfs/docker_data/haven.old`).
3. Create a new empty directory: `mkdir -p /mnt/ssd/nfs/docker_data/haven`.
4. Extract the chosen tarball into it. Tarballs are on the NFS backup volume (`192.168.0.238:/export/alpha/backup/docker`); use the path where that share is mounted on the host you run the restore from, or copy the file from the NFS server:
   ```bash
   tar xzf /path/to/backups/haven-YYYYMMDD-HHMM.tar.gz -C /mnt/ssd/nfs/docker_data/haven
   ```
5. Restore ownership if needed: `chown -R 1000:1000 /mnt/ssd/nfs/docker_data/haven`.
6. Start the stack again. Haven will use the restored SQLite DB and files.

## 8. Troubleshooting

### Backup: "Permission denied" writing to `/backups`

The backup container runs as **root**. If the NFS export uses **root_squash** (default), root on the client is mapped to **nobody** on the NFS server, so the export directory must be writable by that user.

**On the NFS server** (e.g. 192.168.0.238), make the backup export writable by `nobody`:

```bash
sudo chown -R nobody:nogroup /export/alpha/backup/docker
sudo chmod 775 /export/alpha/backup/docker
```

If your NFS server uses a different squashed user (e.g. `nfsnobody`), use that user instead of `nobody`. Alternatively, you can export this share with `no_root_squash` so root in the container stays root on the server (less secure; only if you control the NFS server and accept the risk).

### rclone: "Failed to save config" or "device or resource busy"

The rclone config file is mounted **read-write** so rclone can refresh OAuth tokens. Ensure the host path (e.g. `/mnt/ssd/nfs/docker_data/haven/rclone/rclone.conf`) is writable by the user running the container. If you previously had it read-only (`:ro`), remove `:ro` from the volume mount in the stack and redeploy.

### rclone: "directory not found" when listing or uploading

The path in `RCLONE_REMOTE_PATH` (e.g. `haven_backups`) must be an **existing folder** on Google Drive. Create the folder in drive.google.com (in the account or shared drive your remote uses), or create it with rclone from a machine where rclone is configured: `rclone mkdir gdrive:haven_backups`. Then redeploy or re-run the backup.

## 9. Files added by this setup

| Path | Purpose |
|------|---------|
| `docker-compose.portainer.yml` | Stack definition (Haven + backup sidecar, bind mount, NFS volume, env). |
| `deploymentscripts/backup/Dockerfile` | Backup container image (Alpine, cron, rclone, backup script). |
| `deploymentscripts/backup/backup.sh` | Script: tar, corruption checks, rclone upload, retention, webhook on failure. |
| `deploymentscripts/backup/crontab` | Cron schedule (daily 02:00). |

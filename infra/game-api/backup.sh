#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /opt/remine
backup_dir="/opt/remine/backups/daily-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -m 700 "$backup_dir"
# Redis creates an RDB while continuing to journal subsequent writes to AOF.
docker compose exec -T falkordb sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli --rdb /data/backup.rdb' </dev/null
cp database/backup.rdb "$backup_dir/database.rdb"
tar -czf "$backup_dir/media-and-keys.tar.gz" data api.env database.env signing
sha256sum "$backup_dir/database.rdb" "$backup_dir/media-and-keys.tar.gz" > "$backup_dir/SHA256SUMS"
# Retain one week on this VPS; no external backup destination has been configured.
find /opt/remine/backups -maxdepth 1 -type d -name 'daily-*' -mtime +7 -exec rm -rf -- {} +

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "ERRO: .env ausente"
  exit 1
fi

set -a
source .env
set +a

STAMP="$(date +%Y%m%d_%H%M%S)"
DEST="$ROOT/backups/$STAMP"
mkdir -p "$DEST"

echo "Backup MySQL..."
docker compose exec -T mysql sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases --single-transaction --routines --events --triggers' | gzip > "$DEST/mysql-all.sql.gz"

echo "Backup dados persistentes do Totem..."
docker compose --profile tools run --rm --no-deps backup-helper sh -c 'tar -czf - -C /source/totem .' > "$DEST/totem-data.tar.gz"

sha256sum "$DEST"/* > "$DEST/SHA256SUMS"

RETENTION="${BACKUP_RETENTION_DAYS:-30}"
find "$ROOT/backups" -mindepth 1 -maxdepth 1 -type d -mtime "+$RETENTION" -exec rm -rf {} +

echo "Backup concluído: $DEST"

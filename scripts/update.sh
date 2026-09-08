#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Atualiza somente para os refs explicitamente aprovados em modules/modules.list.
# Não há git pull automático de main e não há pull implícito de imagens-base.
./scripts/bootstrap.sh
./scripts/preflight.sh

docker compose build
docker compose up -d --remove-orphans

docker compose ps

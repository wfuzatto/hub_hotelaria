#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/bootstrap.sh
./scripts/preflight.sh

docker compose build --pull
docker compose up -d --remove-orphans

docker compose ps

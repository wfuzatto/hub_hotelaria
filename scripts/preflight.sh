#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
for cmd in docker git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERRO: comando ausente: $cmd"
    fail=1
  fi
done

if ! docker compose version >/dev/null 2>&1; then
  echo "ERRO: Docker Compose v2 não disponível"
  fail=1
fi

if [[ ! -f .env ]]; then
  echo "ERRO: .env ausente. Execute: cp .env.example .env"
  fail=1
else
  if grep -q 'CHANGE_ME' .env; then
    echo "ERRO: .env ainda contém segredos CHANGE_ME"
    fail=1
  fi
  if grep -Eq '=(hub|totem|face)\.example\.com$' .env; then
    echo "ERRO: troque os domínios example.com no .env"
    fail=1
  fi
fi

for dir in modules/totem_autoatendimento modules/face_scanner; do
  if [[ ! -d "$dir" ]]; then
    echo "ERRO: módulo ausente: $dir (rode ./scripts/bootstrap.sh)"
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

docker compose config >/dev/null

echo "Preflight OK."

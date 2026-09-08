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

if command -v docker >/dev/null 2>&1; then
  if ! docker info >/dev/null 2>&1; then
    echo "ERRO: Docker daemon não está acessível"
    fail=1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "ERRO: Docker Compose v2 não disponível"
    fail=1
  fi
fi

if [[ ! -f .env ]]; then
  echo "ERRO: .env ausente. Execute: cp .env.example .env"
  fail=1
else
  chmod 600 .env
  if grep -q 'CHANGE_ME' .env; then
    echo "ERRO: .env ainda contém segredos CHANGE_ME"
    fail=1
  fi
  if grep -Eq '=(hub|totem|face)\.example\.com$' .env; then
    echo "ERRO: troque os domínios example.com no .env"
    fail=1
  fi
  if grep -Eq '^ACME_EMAIL=.*@example\.com$' .env; then
    echo "ERRO: troque o ACME_EMAIL de exemplo no .env"
    fail=1
  fi
fi

while IFS='|' read -r dest repo ref; do
  [[ -z "${dest:-}" || "$dest" =~ ^[[:space:]]*# ]] && continue
  dest="${dest//[[:space:]]/}"
  ref="${ref//[[:space:]]/}"
  dir="modules/$dest"
  if [[ ! -d "$dir/.git" ]]; then
    echo "ERRO: módulo ausente: $dir (rode ./scripts/bootstrap.sh)"
    fail=1
    continue
  fi
  actual="$(git -C "$dir" rev-parse HEAD)"
  expected="$(git -C "$dir" rev-parse "${ref}^{commit}" 2>/dev/null || true)"
  if [[ -z "$expected" || "$actual" != "$expected" ]]; then
    echo "ERRO: versão de $dest divergente. atual=$actual esperado=${expected:-$ref}"
    fail=1
  fi
done < modules/modules.list

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

docker compose config >/dev/null

echo "Preflight OK."

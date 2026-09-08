#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_PULL=0
USE_GPU="${USE_GPU:-0}"

for arg in "$@"; do
  case "$arg" in
    --no-pull) SKIP_PULL=1 ;;
    --gpu) USE_GPU=1 ;;
    *)
      echo "Uso: $0 [--gpu] [--no-pull]"
      exit 2
      ;;
  esac
done

if [[ ! -f .env ]]; then
  echo "ERRO: .env ausente. Copie .env.example para .env e configure o ambiente."
  exit 1
fi

# Atualiza primeiro o repositório pai. Se o próprio script mudar durante o
# fast-forward, reinicia a execução usando a nova versão do arquivo.
if [[ "$SKIP_PULL" -eq 0 ]]; then
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "ERRO: hub_hotelaria possui alterações locais em arquivos versionados."
    git status --short
    echo "Faça commit/stash antes de atualizar; nada foi sobrescrito."
    exit 1
  fi

  echo "[hub] buscando atualização do main..."
  git fetch --prune origin main
  local_sha="$(git rev-parse HEAD)"
  remote_sha="$(git rev-parse origin/main)"

  if ! git merge-base --is-ancestor "$local_sha" "$remote_sha"; then
    echo "ERRO: o checkout local divergiu de origin/main. Atualização automática abortada."
    echo "local=$local_sha"
    echo "origin/main=$remote_sha"
    exit 1
  fi

  if [[ "$local_sha" != "$remote_sha" ]]; then
    echo "[hub] fast-forward $local_sha -> $remote_sha"
    git merge --ff-only origin/main
    if [[ "$USE_GPU" == "1" ]]; then
      exec "$ROOT/scripts/update.sh" --no-pull --gpu
    else
      exec "$ROOT/scripts/update.sh" --no-pull
    fi
  fi
fi

# Baixa/posiciona cada módulo exatamente no commit homologado de
# modules/modules.list. Produção nunca acompanha main dos módulos diretamente.
echo "[modules] preparando versões aprovadas..."
./scripts/bootstrap.sh

echo "[preflight] validando host/configuração..."
./scripts/preflight.sh

COMPOSE=(docker compose -f compose.yml)
if [[ "$USE_GPU" == "1" ]]; then
  echo "[gpu] override NVIDIA habilitado"
  COMPOSE+=( -f compose.gpu.yml )
fi

# Faz backup antes de alterar containers quando já existe uma instalação em
# execução. Em primeiro deploy não há banco saudável e esta etapa é ignorada.
mysql_cid="$(docker compose -f compose.yml ps -q mysql 2>/dev/null || true)"
if [[ -n "$mysql_cid" ]]; then
  mysql_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$mysql_cid" 2>/dev/null || true)"
  if [[ "$mysql_health" == "healthy" ]]; then
    echo "[backup] criando backup pré-atualização..."
    ./scripts/backup.sh
  else
    echo "[backup] MySQL não está healthy; backup automático pré-update foi ignorado."
  fi
fi

echo "[build] construindo imagens locais..."
"${COMPOSE[@]}" build

echo "[deploy] aplicando stack..."
"${COMPOSE[@]}" up -d --remove-orphans

# Espera os healthchecks dos serviços críticos. Isso evita informar sucesso
# enquanto algum container ainda está reiniciando ou unhealthy.
SERVICES=(gateway mysql hub-core totem-api face-scanner)
DEADLINE=$((SECONDS + 180))

while true; do
  all_ok=1
  summary=""

  for service in "${SERVICES[@]}"; do
    cid="$("${COMPOSE[@]}" ps -q "$service" 2>/dev/null || true)"
    if [[ -z "$cid" ]]; then
      state="missing"
      all_ok=0
    else
      state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || true)"
      if [[ "$state" != "healthy" && "$state" != "running" ]]; then
        all_ok=0
      fi
    fi
    summary+="$service=$state "
  done

  if [[ "$all_ok" -eq 1 ]]; then
    echo "[health] $summary"
    break
  fi

  if (( SECONDS >= DEADLINE )); then
    echo "ERRO: timeout aguardando serviços saudáveis: $summary"
    "${COMPOSE[@]}" ps
    echo "Consulte: ${COMPOSE[*]} logs --tail=200"
    exit 1
  fi

  printf '\r[health] aguardando: %s' "$summary"
  sleep 3
done
printf '\n'

"${COMPOSE[@]}" ps

echo "Atualização Docker concluída com sucesso."

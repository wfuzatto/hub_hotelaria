#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_PULL=0
USE_GPU="${USE_GPU:-0}"
EDGE_MODE="${EDGE_MODE:-host}"

for arg in "$@"; do
  case "$arg" in
    --no-pull) SKIP_PULL=1 ;;
    --gpu) USE_GPU=1 ;;
    --docker-edge) EDGE_MODE=docker ;;
    --host-edge) EDGE_MODE=host ;;
    *)
      echo "Uso: $0 [--gpu] [--host-edge|--docker-edge] [--no-pull]"
      exit 2
      ;;
  esac
done

if [[ ! -f .env ]]; then
  echo "ERRO: .env ausente. Copie .env.example para .env e configure o ambiente."
  exit 1
fi

# Atualiza primeiro o repositório pai. Se o próprio script mudar durante o
# fast-forward, reinicia a execução usando a nova versão e o mesmo modo.
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
    args=(--no-pull)
    [[ "$USE_GPU" == "1" ]] && args+=(--gpu)
    [[ "$EDGE_MODE" == "docker" ]] && args+=(--docker-edge) || args+=(--host-edge)
    exec "$ROOT/scripts/update.sh" "${args[@]}"
  fi
fi

echo "[mode] edge=$EDGE_MODE gpu=$USE_GPU"

# Baixa/posiciona cada módulo exatamente no commit homologado de
# modules/modules.list. Produção nunca acompanha main dos módulos diretamente.
echo "[modules] preparando versões aprovadas..."
./scripts/bootstrap.sh

echo "[preflight] validando host/configuração..."
EDGE_MODE="$EDGE_MODE" USE_GPU="$USE_GPU" ./scripts/preflight.sh

COMPOSE=(docker compose -f compose.yml)
if [[ "$EDGE_MODE" == "host" ]]; then
  # Caddy/NGINX já existentes no Ubuntu continuam na borda. Somente 127.0.0.1
  # recebe portas do Totem/HUB/Totem Food; Face Scanner e MySQL ficam internos.
  COMPOSE+=( -f compose.host-edge.yml )
else
  # Use apenas depois que 80/443 forem liberadas no host.
  COMPOSE+=( --profile docker-edge )
fi
if [[ "$USE_GPU" == "1" ]]; then
  echo "[gpu] override NVIDIA habilitado"
  COMPOSE+=( -f compose.gpu.yml )
fi

# Faz backup antes de alterar containers quando já existe uma instalação em
# execução. O dump usa --all-databases e inclui hub_hotelaria + totem_food.
mysql_cid="$(docker compose -f compose.yml ps -q mysql 2>/dev/null || true)"
if [[ -n "$mysql_cid" ]]; then
  mysql_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$mysql_cid" 2>/dev/null || true)"
  if [[ "$mysql_health" == "healthy" ]]; then
    echo "[backup] criando backup pré-atualização..."
    ./scripts/backup.sh
  else
    echo "[backup] MySQL Docker não está healthy; backup automático pré-update foi ignorado."
  fi
fi

echo "[build] construindo imagens locais..."
"${COMPOSE[@]}" build

# O Totem Food usa o mesmo MySQL do HUB, porém em banco isolado. Primeiro
# garante que o MySQL esteja saudável; depois cria banco/permissão idempotentes.
echo "[db] garantindo MySQL e banco totem_food..."
"${COMPOSE[@]}" up -d mysql

mysql_deadline=$((SECONDS + 180))
while true; do
  mysql_cid="$("${COMPOSE[@]}" ps -q mysql 2>/dev/null || true)"
  mysql_state=""
  if [[ -n "$mysql_cid" ]]; then
    mysql_state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$mysql_cid" 2>/dev/null || true)"
  fi

  if [[ "$mysql_state" == "healthy" ]]; then
    break
  fi

  if (( SECONDS >= mysql_deadline )); then
    echo "ERRO: timeout aguardando MySQL saudável: ${mysql_state:-missing}"
    "${COMPOSE[@]}" ps
    exit 1
  fi

  printf '\r[db] aguardando MySQL: %s' "${mysql_state:-missing}"
  sleep 3
done
printf '\n'

"${COMPOSE[@]}" exec -T mysql sh -ec \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`totem_food\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci; GRANT ALL PRIVILEGES ON \`totem_food\`.* TO \`$MYSQL_USER\`@\`%\`; FLUSH PRIVILEGES;"'

echo "[deploy] aplicando stack..."
"${COMPOSE[@]}" up -d --remove-orphans

SERVICES=(mysql hub-core totem-api totem-food face-scanner)
if [[ "$EDGE_MODE" == "docker" ]]; then
  SERVICES=(gateway "${SERVICES[@]}")
fi
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

if [[ "$EDGE_MODE" == "host" ]]; then
  echo "Totem Hotel:  http://${TOTEM_LOCAL_BIND:-127.0.0.1}:${TOTEM_LOCAL_PORT:-3080} (somente host)"
  echo "Totem Food:   http://${TOTEM_FOOD_LOCAL_BIND:-127.0.0.1}:${TOTEM_FOOD_LOCAL_PORT:-3085} (somente host)"
  echo "HUB Docker:   http://${HUB_LOCAL_BIND:-127.0.0.1}:${HUB_LOCAL_PORT:-3083} (somente host)"
  echo "Face Scanner: somente rede Docker em face-scanner:8091"
fi

echo "Atualização Docker concluída com sucesso."

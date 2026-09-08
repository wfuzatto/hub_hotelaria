#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$ROOT/modules/modules.list"

mkdir -p "$ROOT/modules"

while IFS='|' read -r dest repo; do
  [[ -z "${dest:-}" || "$dest" =~ ^[[:space:]]*# ]] && continue
  dest="${dest//[[:space:]]/}"
  repo="${repo//[[:space:]]/}"
  target="$ROOT/modules/$dest"

  if [[ -d "$target/.git" ]]; then
    echo "[update] $dest"
    git -C "$target" fetch --prune
    git -C "$target" pull --ff-only
  else
    echo "[clone] $dest"
    git clone "$repo" "$target"
  fi
done < "$LIST"

echo "Módulos preparados."

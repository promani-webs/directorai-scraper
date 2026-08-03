#!/usr/bin/env bash
# Sincroniza este fork con gosom/google-maps-scraper aplicando la politica
# documentada en UPSTREAM-SYNC.md:
#   - Dockerfile: SIEMPRE la version del fork (ours)
#   - Rutas de DELETE_PATHS: nunca vuelven a entrar en el repo
#   - go.sum en conflicto: se toma upstream y `go mod tidy` lo regenera
#   - Resto de conflictos: quedan sin resolver y el script sale con codigo 2
#
# Codigos de salida: 0 = al dia o merge completado, 2 = conflictos manuales.
set -uo pipefail
cd "$(dirname "$0")/.."

UPSTREAM_URL=https://github.com/gosom/google-maps-scraper
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
git fetch -q upstream

if git merge-base --is-ancestor upstream/main HEAD; then
  echo "Ya al dia con upstream."
  exit 0
fi

OURS_PATHS=(Dockerfile)
DELETE_PATHS=(
  cmd rqueue api httpext ratelimit scraper env admin infra saas
  skills docs img examples local sponsors testdata-saas
  README.md Makefile AGENTS.md SECURITY.md Dockerfile.saas
  docker-compose.dev.yaml docker-compose.saas.yaml PROVISION banner.png
  example-queries.txt gmaps-extractor.md migration-pro.md netnut.md
  scrap_io.md serpapi.md talordata.md webshare.md "MacOS instructions.md"
  lint.go .github/FUNDING.yaml .github/workflows/build.yml
  .github/workflows/publish.yml
)

git merge --no-commit upstream/main >/dev/null 2>&1
merge_code=$?

for p in "${DELETE_PATHS[@]}"; do
  git rm -rq --ignore-unmatch -- "$p" >/dev/null 2>&1 || true
done

for p in "${OURS_PATHS[@]}"; do
  if git ls-files -u -- "$p" | grep -q .; then
    git checkout --ours -- "$p" && git add -- "$p"
  fi
done

if git ls-files -u -- go.sum | grep -q .; then
  git checkout --theirs -- go.sum && git add go.sum
fi

if git ls-files -u | grep -q .; then
  echo "CONFLICTOS pendientes de resolucion manual:" >&2
  git ls-files -u | cut -f2 | sort -u >&2
  exit 2
fi

if command -v go >/dev/null 2>&1; then
  go mod tidy && git add go.mod go.sum
fi

git commit -q -m "Merge upstream gosom/google-maps-scraper ($(git rev-parse --short upstream/main))"
echo "Merge completado: $(git rev-parse --short HEAD)"
bash scripts/check-compat.sh

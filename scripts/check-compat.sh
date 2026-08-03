#!/usr/bin/env bash
# Verifica que las personalizaciones que DirectorAI.py necesita siguen
# presentes tras un sync con upstream. Se ejecuta en CI y en local.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
err() { echo "COMPAT FAIL: $*" >&2; fail=1; }

grep -q 'scraped successfully' main.go \
  || err "main.go: falta el marcador 'scraped successfully' (DirectorAI lo usa para detectar fin OK)"
grep -q 'filteringHandler' main.go \
  || err "main.go: falta el filtro de logs de playwright-go"
grep -q '"exit-on-inactivity", 30\*time.Minute' runner/runner.go \
  || err "runner/runner.go: el default de -exit-on-inactivity debe ser 30*time.Minute"
grep -q 'promani-webs/scrapemate' go.mod \
  || err "go.mod: falta el replace de scrapemate (fix del bug de inactividad)"
grep -q 'WaitForSelector(scrollSelector, 60\*time.Second)' gmaps/job.go \
  || err "gmaps/job.go: falta la espera de 60s del feed antes del scroll"
grep -q 'if (!el)' gmaps/job.go \
  || err "gmaps/job.go: falta la guarda null en el JS del scroll"
grep -q 'func Banner() {' runner/runner.go && ! grep -q 'Fprintln(os.Stderr, banner(' runner/runner.go \
  || err "runner/runner.go: Banner() debe estar vacio (DirectorAI parsea la salida)"

# Columnas CSV que DirectorAI.py consume por nombre. Anadir columnas nuevas
# es seguro; renombrar o quitar cualquiera de estas rompe DirectorAI.
for col in input_id link title category address open_hours popular_times \
           website phone review_count review_rating reviews_per_rating \
           latitude longitude status descriptions thumbnail price_range \
           about user_reviews complete_address emails; do
  grep -q "\"$col\"" gmaps/entry.go || err "gmaps/entry.go: falta la columna CSV '$col'"
done

# DRIVER_VER del Dockerfile debe coincidir con playwrightCliVersion del
# playwright-go que resuelve go.mod (si hay toolchain de Go disponible).
if command -v go >/dev/null 2>&1; then
  mod=$(go list -m -f '{{.Path}}@{{.Version}}' github.com/mxschmitt/playwright-go 2>/dev/null || true)
  if [ -n "$mod" ]; then
    go mod download github.com/mxschmitt/playwright-go >/dev/null 2>&1 || true
    src="$(go env GOMODCACHE)/$mod/run.go"
    if [ -f "$src" ]; then
      cli=$(grep -o 'playwrightCliVersion = "[0-9.]*"' "$src" | grep -o '[0-9][0-9.]*')
      dv=$(grep -o 'DRIVER_VER=[0-9.]*' Dockerfile | cut -d= -f2)
      [ "$cli" = "$dv" ] \
        || err "Dockerfile: DRIVER_VER=$dv pero playwright-go espera $cli (actualiza tambien PLAYWRIGHT_IMAGE)"
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "COMPAT OK"
fi
exit "$fail"

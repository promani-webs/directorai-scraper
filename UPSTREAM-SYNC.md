# Sincronización con upstream (gosom/google-maps-scraper)

Este repo es un fork de [gosom/google-maps-scraper](https://github.com/gosom/google-maps-scraper)
adaptado para **DirectorAI**. DirectorAI.py descarga el ZIP de `main` de
este repo y construye la imagen Docker con el `Dockerfile` del repo, así
que **`main` es producción**: no mergear nada a `main` sin que el CI esté
en verde.

## Personalizaciones del fork (lo que NUNCA se debe perder)

| Fichero | Personalización | Por qué |
|---|---|---|
| `main.go` | `filteringHandler` (filtra logs "Downloading browsers/driver") | Salida limpia para DirectorAI |
| `main.go` | `log.Println("scraped successfully")` al acabar | **DirectorAI.py detecta el fin OK buscando esta cadena** (junto a "scrapemate exited") |
| `runner/runner.go` | default de `-exit-on-inactivity` = `30*time.Minute` (upstream: 0 = desactivado) | Red de seguridad si el caller no pasa el flag |
| `runner/runner.go` | `Banner()` vacío | Sin ruido en stderr |
| `gmaps/job.go` | `WaitForSelector(feed, 60s)` antes del scroll | Upstream solo espera 10s; en portátiles/red lentos el feed tarda más y el job moriría |
| `gmaps/job.go` | `if (!el) return -1` en el JS del scroll | Evita excepción JS si el feed desaparece |
| `Dockerfile` | Reescrito: base MCR Playwright + caché del driver playwright-go pre-sembrada (node + package) | Build sin depender de archive.ubuntu.com ni del CDN del driver (el zip 1.57+ daba 404). Autocontenido y reproducible |
| `go.mod` | `replace gosom/scrapemate => promani-webs/scrapemate` | Fix del bug de inactividad de scrapemate (aborta antes del primer job); **upstream aún no lo ha arreglado** (verificado en scrapemate v1.3.0) |
| (borrados) | README, docs, img, sponsors, admin/, infra/, saas/, cmd/, rqueue/, api/, httpext/, ratelimit/, scraper/, env/, skills/, examples/ | El fork solo mantiene lo necesario para compilar el binario CLI. El código SaaS ni siquiera compilaba sin admin/infra |

`scripts/check-compat.sh` verifica todo esto (más las columnas CSV que
DirectorAI.py lee por nombre y que `DRIVER_VER` del Dockerfile coincide
con el driver que espera playwright-go). CI lo ejecuta en cada PR.

## Cómo se sincroniza

### Automático

`.github/workflows/upstream-sync.yml` corre cada lunes (y a mano desde
la pestaña Actions → "Sync upstream" → Run workflow):

1. Ejecuta `scripts/sync-upstream.sh` (merge de `upstream/main` con la
   política: Dockerfile siempre nuestro, rutas borradas siguen borradas,
   `go.sum` se regenera con `go mod tidy`).
2. Si el merge queda limpio: build + vet + tests + check-compat, empuja
   la rama `upstream-sync` y **abre un PR** (nunca toca `main` directo).
3. Si hay conflictos fuera de la política: aborta y **abre un issue**
   con los ficheros; se resuelve en local (o se lo pides a Claude Code).

Requisito único (una vez): en GitHub → Settings → Actions → General →
Workflow permissions, activar **"Allow GitHub Actions to create and
approve pull requests"**. Nota: GitHub desactiva los crons tras 60 días
sin actividad en el repo; el workflow_dispatch manual siempre funciona.

### Binario WSL (release rodante `wsl-latest`)

`.github/workflows/release-wsl.yml` se dispara en cada push a `main`:
verifica (build + vet + tests + check-compat), compila el binario
`linux/amd64` estático y lo publica machacando el release `wsl-latest`.
URL estable que consume el modo WSL de DirectorAI.py:

```
https://github.com/promani-webs/directorai-scraper/releases/download/wsl-latest/directorai-scraper-linux-amd64
```

Consecuencia: al mergear el PR semanal de sync, el binario WSL nuevo se
publica solo — Docker y WSL quedan siempre en la misma versión.

### Manual (local)

```bash
bash scripts/sync-upstream.sh
```

En Windows, desde Git Bash o WSL (necesita `go` en el PATH para el
`go mod tidy` y el check completo; sin `go` hace el merge igualmente).

## Al actualizar versiones de Playwright

Si upstream sube `playwright-go` (o scrapemate lo sube), hay que tocar
el `Dockerfile` a mano — es el único mantenimiento periódico real:

1. `DRIVER_VER` = `playwrightCliVersion` del `run.go` del playwright-go
   resuelto (check-compat.sh te dice el valor esperado si no cuadra).
2. `PLAYWRIGHT_IMAGE` = `mcr.microsoft.com/playwright:v<esa versión>-jammy`
   (comprobar que el tag existe: `docker manifest inspect <imagen>`).

## Al actualizar scrapemate

El fork `promani-webs/scrapemate` lleva el fix de inactividad
(`inactivityRef`/`startTime` en `scrapemate.go`). Cuando upstream saque
scrapemate nuevo:

```bash
git clone https://github.com/promani-webs/scrapemate && cd scrapemate
git remote add upstream https://github.com/gosom/scrapemate
git fetch upstream && git merge upstream/main   # el guard sobrevive salvo que toquen esa zona
git push origin main
```

Después, en este repo: `go mod edit -replace github.com/gosom/scrapemate=github.com/promani-webs/scrapemate@<sha>`
y `go mod tidy`. Antes de nada, comprobar si upstream ya arregló el bug
(buscar `IsZero` cerca del check de `exitOnInactivity` en
`scrapemate.go`); si lo arreglaron, quitar el replace y simplificar.

# Deploying ChenWeb and Kratos Binaries to the China Box

**Date:** 2026-09-15 (rev 2026-09-16: `mise run build-server-linux` and
`deploy-server-china.sh` now ship and install `doc-review.local.toml` and
`product-review.local.toml` automatically, §1/§3 — both had been silently missing from
this workflow, `product-review.local.toml` was never deployed at all)
**Scope:** The three-step workflow for shipping a new ChenWeb build to the China
production box `210.5.158.91` (`rssvr19`, `https://onto.bzton.cn`): build on the Mac,
copy to the box by hand, deploy on the box. This is the **build/ship** runbook — for
starting/restarting already-installed services, box facts (SSH access, `su -`, systemd
units), and troubleshooting, see `2026090701-devdoc-start-system-onto.md`. For the
original (pre-script) manual procedure and why this box deviates from a normal deploy,
see `2026072401-devdoc-deploy-production.md` and
`2026073001-devdoc-deploy-production-china-dingbo.md`. §4 below covers the parallel
Kratos procedure, which — unlike ChenWeb — has no mise task or deploy script; it's fully
manual.

There is no Go toolchain, `mise`, or `air` on the box — every ChenWeb Go binary is
cross-compiled on the Mac and shipped over as a prebuilt `linux/amd64` executable.

## Overview

```
1. Build   (Mac, mise task)     mise run build-server-linux   -> /tmp/chenweb-deploy/
2. Copy    (Mac, manual)        scp -P 8822 -r /tmp/chenweb-deploy gui@210.5.158.91:~/
3. Deploy  (box, script, root)  bash ~/chenweb-deploy/deploy-server-china.sh ~/chenweb-deploy
```

Step 1 and step 3 are each a single script invocation. Step 2 is a manual `scp` — there
is deliberately no script that pushes binaries onto the box directly, so a human always
looks at what's about to ship before it lands on prod.

## 1. Build the binaries (Mac)

### 1.1 Quick Deployment
Step 1: on the Mac machine:
```text
cd ~/Workspace/ChenWeb
sh shell_server_build_rpc.sh
```
It builds the binary and downloads the binary to Runshen 19 (210.5.158.91),
in the staging directory: '/home/gui/Workspace/ChenWeb/deploy_staging.

Step 2: on Runshen 19
```text
su (must be in root)
cd /home/gui/Workspace/ChenWeb
sh shell_server_deploy.sh
exit (the root)
sh shell_server_restart.sh
```

### 1.2 Deployment in Details
From `ChenWeb/`:

```bash
mise run build-server-linux                 # all five linux/amd64 binaries + .sha256
BINS=server mise run build-server-linux      # just server-linux (fast path)
BINS=server,doc-processor mise run build-server-linux   # a comma-separated subset
```

Valid `BINS` names: `server`, `doc-processor`, `parser-result-converter`, `doc-service`,
`create-admin`. Omit `BINS` to build all five.

What the task does (`ChenWeb/mise.toml`, `[tasks.build-server-linux]`):

- Wipes and recreates `/tmp/chenweb-deploy/`.
- If `server` is among the selected binaries, first rebuilds the embedded frontend
  (`cd web && bun run build`, synced into `server/api/webbuild/`, which is gitignored)
  — the `server` binary is the only one that embeds the frontend
  (`//go:embed all:webbuild` in `server/api/routes.go`), and the committed copy is
  stale, so this step is not optional when `server` is in the set.
- Cross-compiles each selected binary: `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build
  -trimpath -buildvcs=false -ldflags "-s -w"`.
- Writes a `sha256sum`-compatible `<name>-linux.sha256` next to each binary.
- Copies `ChenWeb/scripts/deploy-server-china.sh` into the output directory too, so the
  whole `/tmp/chenweb-deploy/` folder is self-contained — build output and the script
  that installs it travel together.
- Copies `project_migrations/` and `shared_migrations/` into the output directory.
  **This is not optional and is not per-binary** — it ships on every build regardless of
  `BINS`. `config.RunMigrations` reads migration files from **disk** at each binary's
  startup (`sharedgoose.RunProjectMigrations` → `os.DirFS` on `PROJECT_MIGRATION_DIR`),
  *not* from a `go:embed` FS, so a binaries-only payload leaves the box's migration
  directory frozen wherever the last copy left it: goose dutifully applies everything it
  can see, records a correct-looking max version, and the newer tables simply never get
  created. That failure is silent until something queries a missing table
  (`pq: relation "kb.data_sync_state" does not exist`). Shipping binaries without
  migrations is what caused exactly that on 2026-09-16, when the box sat 22 migrations
  behind.
- Copies the two `*.local.toml` reviewer configs — `doc-review.local.toml` and
  `product-review.local.toml` — into the output directory (added 2026-09-16, same day
  both were separately discovered missing on `onto.bzton.cn`). **Also not optional and
  not per-binary**, same reasoning as migrations: despite the `.local.` name these are
  real, git-tracked repo-root files (unlike gitignored `mise.local.toml`/
  `config.local.toml`), read from disk on demand — `doc-reviews.GetDocReviewConfig()`
  and `productreviews.GetConfig()` — not `go:embed`'d, so a binaries-only payload leaves
  them invisible to the box just like `prompts/` (see the Gotcha below). A missing
  `doc-review.local.toml` silently disables 6 reviewer aspects (non-fatal); a missing
  `product-review.local.toml` fails **every** Product Review build request outright
  (`newBuilder()` treats a `nil` config as fatal). Warns to stderr and skips a file that
  isn't present at the repo root rather than failing the build.
- Writes a `MANIFEST` (git rev, short rev, dirty flag, build timestamp, build host,
  which binaries were built, the migration file counts shipped, and which reviewer
  configs were staged) — check this on the box if you ever need to confirm what's
  actually running (`cat ~/Workspace/ChenWeb/MANIFEST` isn't kept on the box itself; the
  manifest lives only in the `/tmp/chenweb-deploy` you shipped — copy it over too, or
  note the git rev before you `rm` the local `/tmp` copy).

Output:

```
/tmp/chenweb-deploy/
  server-linux, server-linux.sha256
  doc-processor-linux, doc-processor-linux.sha256
  parser-result-converter-linux, parser-result-converter-linux.sha256
  doc-service-linux, doc-service-linux.sha256
  create-admin-linux, create-admin-linux.sha256
  deploy-server-china.sh
  project_migrations/          <- all *.sql, shipped on every build
  shared_migrations/           <- all *.sql, shipped on every build
  doc-review.local.toml        <- shipped on every build, skipped+warned if absent
  product-review.local.toml    <- shipped on every build, skipped+warned if absent
  MANIFEST
```

The task's own trailing output prints the exact next commands (steps 2 and 3 below), so
if you forget this doc, `mise run build-server-linux` tells you what to do next.

**Note:** the task `rm -rf`s `/tmp/chenweb-deploy/` at the start of every run — it is
disposable build output, not somewhere to stash unrelated files.

## 2. Download the binaries (manual)

`scp` the whole output directory to the box, as the unprivileged `gui` user (port 8822,
not 22):

```bash
scp -P 8822 -r /tmp/chenweb-deploy gui@210.5.158.91:~/
```

This lands at `~gui/chenweb-deploy/` on the box. There's no deploy account with
broader access — `gui` can receive the files but cannot install them (see below), which
is why step 3 needs `root`.

Sanity-check before moving on, if you want a second pair of eyes on what's about to ship:

```bash
ssh -p 8822 gui@210.5.158.91 'cat ~/chenweb-deploy/MANIFEST'
```

## 3. Deploy the binaries (box, as root)

SSH in and switch to root — `gui` has no sudo, so this is either the root SSH key
(`ssh -p 8822 root@210.5.158.91`) or `su -` from a `gui` session:

```bash
ssh -p 8822 gui@210.5.158.91
su -                       # root password prompt is localized; see below if it hangs
bash ~/chenweb-deploy/deploy-server-china.sh ~/chenweb-deploy [name ...]
```

`root` is required because the script calls `systemctl stop/start` and `install -o
gui -g gui` (chowning back to the unprivileged runtime user) — `gui` cannot do either.

If `su -` seems to hang or reject a correct password, force the locale first — the
prompt is Chinese and breaks naive expect-style matching:

```bash
env LC_ALL=C LANG=C su -
```

**Arguments:** `<dir>` is required (the directory holding the `*-linux` +
`*-linux.sha256` pairs — here, `~/chenweb-deploy`); `[name ...]` is an optional list
restricting the deploy to specific binaries (same valid names as `BINS` above — e.g.
`... deploy-server-china.sh ~/chenweb-deploy server`). Omit the name list to deploy
every `*-linux` binary found in `<dir>`.

**What the script does first — migrations** (before it touches any binary, because
every unit runs goose at startup and reads these directories from disk):

- Skips with a note if the payload has no `project_migrations/` (i.e. it was built before
  migration shipping existed) — so an old payload degrades to the previous behaviour
  rather than erroring.
- Prints the migration files that are **new to the box** and will be applied at the next
  service start. Read this list before continuing; it is the only preview you get.
- Copies them in with `rsync -a` (**additive — never `--delete`**, so a migration the box
  has already applied is never pulled out from under goose's `project_db_migration`
  tracking table), then `chown -R gui:gui`.
- **Migrations are not rolled back** by the per-binary auto-rollback below. Goose down-
  migrations are never run here, so a binary that rolls back still leaves the new schema
  in place. Set `SKIP_MIGRATIONS=1` to deploy binaries only.

**Next — reviewer configs** (also before any binary swap, though timing matters less
here than for migrations since both configs are read on demand, not at startup):

- For each of `doc-review.local.toml` / `product-review.local.toml` present in the
  payload: installs it verbatim to `$CHENWEB_DIR/<name>` (`install -m 0644 -o "$RUN_USER"
  -g "$RUN_USER"`), or reports "already current" if a byte-identical copy is already
  there. No per-box translation — both files only carry symbolic `model`/`prompt` refs.
  A file **absent from the payload** (an old build predating this change) is skipped
  with a note, not an error — same fail-open posture as the migrations block above.
- Always runs regardless of which binary names are passed on the command line, same as
  migrations — cheap enough not to gate on `[ name = server ]` even though only
  `chenweb` reads `product-review.local.toml` and only `doc-processor` reads
  `doc-review.local.toml` in practice.
- Not covered by `SKIP_MIGRATIONS` — there's no equivalent skip flag for configs; they're
  small, idempotent, git-tracked files with no down-migration-style concern.

**What the script does, per binary** (`ChenWeb/scripts/deploy-server-china.sh`):

1. Verifies the `.sha256` checksum and that the file is an ELF 64-bit x86-64 binary —
   catches a corrupted transfer or the wrong architecture before it touches anything.
2. If a binary of the same name is already installed, backs it up to
   `<name>-linux.bak-<timestamp>` and prunes old backups (keeps the 3 most recent,
   `KEEP_BAKS` env var).
3. Maps the binary name to a systemd unit and stops it (`server`→`chenweb`,
   `doc-processor`→`doc-processor`, `parser-result-converter`→`parser-result-converter`,
   `doc-service`→`doc-service`; `create-admin` has no unit — it's a CLI tool, so the
   script just installs it and moves on).
4. Installs the new binary (`install -m 0755 -o gui -g gui`) into
   `~/Workspace/ChenWeb/<name>-linux` and starts the unit.
5. Health-checks: polls `systemctl is-active` for up to 30s; for `chenweb` specifically
   also requires `http://127.0.0.1:8090/` to return `200`.
6. **Auto-rollback on failure** — if the health check doesn't pass, stops the unit,
   restores the most recent `.bak-<timestamp>`, restarts it, dumps the last 50
   `journalctl` lines for the unit, and exits non-zero. A failed deploy of one binary
   does not roll back the others already deployed in the same invocation.
7. On success, prints the unit status and the last ~12 log lines. If `server` was among
   the deployed binaries, also prints `/api/config`'s `enable_phone_login` value as a
   quick smoke signal that the new binary actually answers requests correctly.

**Useful env var overrides** (set before the `bash` invocation):

| Var | Default | Purpose |
|---|---|---|
| `CHENWEB_DIR` | `/home/gui/Workspace/ChenWeb` | install target directory |
| `RUN_USER` | `gui` | owner of the installed binaries |
| `PORT` | `8090` | port used for the `chenweb` HTTP health check |
| `KEEP_BAKS` | `3` | number of `.bak-<timestamp>` copies retained per binary |
| `SKIP_MIGRATIONS` | `0` | set to `1` to leave migration files untouched and deploy binaries only |
| `DRY_RUN` | `0` | set to `1` to print every privileged action instead of running it (also skips the root check, so it can be previewed as `gui`) |

Preview a deploy without touching the box:

```bash
DRY_RUN=1 bash ~/chenweb-deploy/deploy-server-china.sh ~/chenweb-deploy
```

## Verify

```bash
curl -s -o /dev/null -w 'chenweb :8090 -> %{http_code}\n' http://127.0.0.1:8090/     # 200
curl -s -o /dev/null -w 'https edge -> %{http_code}\n' https://onto.bzton.cn/         # 200
journalctl -u chenweb -n 40 --no-pager | grep -v 'goose:'
```

A binary swap only replaces the executable — it does **not** carry config flags, `.env`
changes, Kratos config, or non-Go assets like `prompts/`. Box-side enablement work that
goes with a given feature is tracked separately (e.g. `ChenWeb/deploy/phone-login/` for
the phone-login rollout).

**Gotcha — `prompts/` is not part of the binary and not shipped by this workflow.**
(The sibling `*.local.toml` reviewer configs were the same story until 2026-09-16 — both
`mise run build-server-linux` and `deploy-server-china.sh` now ship and install them
automatically, see §1/§3 above. `prompts/` itself is still **not** automated — it stays a
manual tar/scp, below.)
Hit 2026-09-16: a `server-linux` deploy panicked on startup —
`initialize Pi profiles: load profile "knowledge-guide": read prompt
".../prompts/prompt-agent-knowledge-guide-v1.md": no such file or directory` — because
`server/api/agentservicehandler.LoadProfileRegistry` (`server/api/routes.go:259-266`)
fail-fast-reads every registered profile's prompt file from `PROMPT_DIR`
(`~/Workspace/ChenWeb/prompts` on the box, from `.env`) at startup. The prompt files
were already committed on the Mac but had never been copied to the box — `mise run
build-server-linux`/`deploy-server-china.sh` only ever touch the compiled binaries.
**Auto-rollback caught it** (health check failed → previous binary restored,
`chenweb` kept running), so this is a failed-deploy annoyance, not an outage, but it
will recur for any future profile/prompt addition unless `prompts/` is synced first.
Same applies to `project_migrations/`/`shared_migrations/` (new `.sql` files — goose
just needs them on disk, no rebuild) — see the "per-code-change" file list in
`2026073001-devdoc-deploy-production-china-dingbo.md`.

Fix / prevention — before deploying a `server-linux` build that adds or renames a
prompt file, sync `prompts/` first (tar it — this box's link reliably breaks on
multi-file `scp`/`rsync`, see the china-dingbo devdoc gotcha #8):
```bash
# Mac
tar czf /tmp/chenweb-prompts.tar.gz prompts/
scp -P 8822 /tmp/chenweb-prompts.tar.gz gui@210.5.158.91:~/

# Box (as gui — plain files, no root/service action needed)
ssh -p 8822 gui@210.5.158.91 'cd ~/Workspace/ChenWeb && tar xzf ~/chenweb-prompts.tar.gz'
```
If a deploy already failed this way, the rolled-back-from binary is still sitting in
`~/chenweb-deploy/` on the box — sync `prompts/`, then just re-run
`deploy-server-china.sh` again; no need to rebuild or re-`scp` the binary.

### Workspace timezone and `config.local.toml`

ChenWeb loads `config.toml` first and then merges the optional sibling
`config.local.toml`; local values override the base file. `config.local.toml` is
machine-specific and is intentionally not included in the binary deployment payload.
Do not copy the Mac's local file to the China box.

The China box must have this local setting:

```toml
[llm]
workspace_timezone = "Asia/Shanghai"
```

On the Mac, use the workspace timezone appropriate for the Mac deployment, normally:

```toml
[llm]
workspace_timezone = "America/Chicago"
```

After changing the file, restart every ChenWeb process that captures or reports LLM
usage (`chenweb` and `doc-processor`). The timezone controls the workspace-day boundary,
daily reconciliation, Today/Yesterday filters, and hourly Spend Reports labels. It does
not change the stored UTC instant in `llm_usage_event.request_started_at`; it only
converts that instant when assigning a workspace day or displaying an hourly bucket.

Verify the file and service restart on the China box:

```bash
grep -A2 '^\[llm\]' ~/Workspace/ChenWeb/config.local.toml
systemctl restart doc-processor
systemctl restart chenweb
journalctl -u doc-processor -n 40 --no-pager | grep -i timezone
```

For the complete timezone contract and troubleshooting examples, see
`2026092302-devdoc-workspace-timezones.md`.

## 4. Kratos (manual — no mise task or deploy script)

Kratos is a **separate project** (`~/Workspace/Kratos`, own `CLAUDE.md`/repo) that ships
to the same box, but its build/deploy path was never packaged the way ChenWeb's was —
there is no `build-kratos-linux` mise task and no `deploy-kratos-china.sh`. Everything
below is done by hand. `Kratos/mise.toml` only has `[tasks.build-kratos]`, which builds
a **native** (Mac) binary for local dev — it has no cross-compile flags.

**First — figure out whether you actually need to rebuild the binary at all.** Most
Kratos changes don't:

- `kratos.yml`, `identity.schema.json`, `google_mapper.jsonnet`, `kratos/templates/**`
  are **not** compiled into `kratos-linux` — Kratos reads them from disk at startup
  (`serve --config ./kratos/kratos.yml`, run with `WorkingDirectory=~/Workspace/Kratos`;
  the config in turn points at the schema/templates by path). Changing any of these is a
  **file copy + restart**, not a rebuild:
  ```bash
  scp -P 8822 kratos/kratos.yml gui@210.5.158.91:Workspace/Kratos/kratos/kratos.yml
  # (or identity.schema.json / google_mapper.jsonnet / templates/...)
  ssh -p 8822 gui@210.5.158.91 'env LC_ALL=C LANG=C su -c "systemctl restart kratos"'
  ```
  `kratos.yml` on the box is gitignored and hand-maintained (box paths, port 8090, no
  `mise`) — diff before overwriting, don't blindly copy the Mac's version. See
  `2026090701-devdoc-start-system-onto.md` §2 for the box-specific values that must not
  regress (`SERVE_PUBLIC_BASE_URL`, the fixed-size CORS/return-URL arrays, etc.).
- The binary itself only needs rebuilding when the **vendored `ory/kratos` source is
  upgraded** (`src/kratos/` is a `git clone` of the upstream repo, updated via `mise
  install-kratos` re-pulling it) — this project doesn't otherwise patch Kratos's Go code.

**If a rebuild is actually needed:**

```bash
# Build (Mac) — cross-compile by hand; no mise task does this
cd ~/Workspace/Kratos/src/kratos
GOWORK=off CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o ../../kratos-linux .

# sanity-check before shipping
file ../../kratos-linux                                   # -> ELF 64-bit LSB executable, x86-64
shasum -a 256 ../../kratos-linux

# Copy (manual)
scp -P 8822 ~/Workspace/Kratos/kratos-linux gui@210.5.158.91:Workspace/Kratos/kratos-linux.new

# Deploy (box, as root — no script, so do each step yourself)
ssh -p 8822 gui@210.5.158.91
env LC_ALL=C LANG=C su -
cd /home/gui/Workspace/Kratos
systemctl stop kratos
cp -a kratos-linux kratos-linux.bak-$(date +%Y%m%d-%H%M%S)
mv kratos-linux.new kratos-linux
chown gui:gui kratos-linux && chmod 0755 kratos-linux
systemctl start kratos
curl -s http://127.0.0.1:4433/health/alive; echo          # -> {"status":"ok"}
journalctl -u kratos -n 30 --no-pager
```
If the health check fails, restore the `.bak-<timestamp>` and `systemctl restart
kratos` — there's no automatic rollback here the way `deploy-server-china.sh` does it
for ChenWeb.

`GOWORK=off` matters: `src/kratos/` is upstream `ory/kratos`'s own module (own
`go.mod`), not a workspace member, so it must build against its own `go.mod`/`go.sum`
rather than anything `go.work` would try to resolve.

**Confirming what's actually built/running:** `kratos-linux` embeds Go build info even
though the box has no Go toolchain to read it with — inspect a *local* copy (the one
you're about to ship, or one scp'd back) from the Mac:
```bash
go version -m ~/Workspace/Kratos/kratos-linux | grep -E 'go1|mod |vcs\.'
```
This prints the exact `ory/kratos` pseudo-version/commit and confirms
`CGO_ENABLED=0 GOOS=linux GOARCH=amd64` were actually used. (The leftover
`Kratos/.cache-kratos-linux/kratos-linux` from the original 2026-07-30 China deploy —
see `2026073001-devdoc-deploy-production-china-dingbo.md` — was built this same way,
from upstream commit `e72261206a31` / 2026-02-13; there's no guarantee that's still
what's running on the box today, only that it's built with matching flags.)

### Config Cookie TTL
Step 1: env var 'COOKIE_TIMEOUT_HOURS'
```text
cd /home/gui/ChenWeb/.env
set/add COOKIE_TIMEOUT_HOURS = 240 in '.env'
```

Step 2: env var 'SESSION_LIFESPAN':
```text
cd /home/gui/Workspace/Kratos
add/update SESSION_LIFESPAN=240h in 'kratos.env'
```

Step 3: restart Kratos

## See also

- `2026090701-devdoc-start-system-onto.md` §2 / §7 — operational context this workflow
  sits inside (box facts, systemd units, Kratos config values, the full service
  dependency chain).
- `2026072401-devdoc-deploy-production.md` — full build + deploy runbook and config-var
  reference predating the scripted flow.
- `2026073001-devdoc-deploy-production-china-dingbo.md` — why this box deviates from a
  normal deploy (Ubuntu 18.04, blocked registries, cross-compiled Kratos, etc.).
- `project_chenweb_dingbo_deployment` (memory) — current deployed state and the
  dingbo→onto rename.

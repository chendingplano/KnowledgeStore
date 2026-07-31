# Deploying ChenWeb to the China box (`210.5.158.91`, `dingbo.bzton.cn`)

**Date:** 2026-07-30
**Scope:** Bringing up ChenWeb + Kratos + NATS + ParadeDB on `210.5.158.91` (ssh port `8822`, user `gui`), a shared company production server in China, for the `dingbo.bzton.cn` domain — cutting the domain over from where it previously ran (the MacMini, see `2026072801-devdoc-switch-app-domain-name.md`).

**Relationship to other devdocs:** `2026072401-devdoc-deploy-production.md` is the general reference (built against `192.168.29.96`, Ubuntu 20.04) — start there for command-level detail on Kratos setup, config.toml/.env variables, goose ordering, etc. This doc only records **where this specific deployment had to deviate**, and the real gotchas hit doing it.

## Why this deployment differs from the reference doc

1. **Ubuntu 18.04 (bionic), not 20.04** — can't be upgraded (other apps on the box depend on it).
2. **Ports 80/443 already owned** by a live production nginx serving real company sites (`bzton-platform-prod.conf`, `bzt.cdbzh.com.conf`, etc.) — same org as this deployment, not a stranger's box.
3. **No further connectivity from the Mac after this session** — everything had to be transferred in one sitting (in practice: several sittings, across a very unreliable link — see below).
4. **`gui` has no sudo at all.** Root is only reachable via `su -` (interactive, needs a real pty) with a separately-provided root password.

## Network reality: extremely variable, sometimes catastrophically slow

- Direct HTTPS from the box to `github.com` works; `raw.githubusercontent.com`, `objects.githubusercontent.com`, `registry-1.docker.io`, `hub.docker.com`, `huggingface.co` are all blocked. The box's configured local proxy (`127.0.0.1:7890`, wired into `/etc/docker/daemon.json`) is itself broken (connection reset).
- **Everything (Kratos binary, NATS/goose/nats binaries, ParadeDB Docker image) was cross-compiled/pulled on the Mac and transferred as files** — never fetched directly on the China box.
- The Mac→China transfer path was wildly inconsistent: at one point sustained ~5KB/s with 15–27 *hour* ETAs on a 341MB file over a VPN tunnel (`utun7`, 402ms RTT) the user had active. Turning the VPN off broke SSH entirely (see below) — turns out `ufw` on the box only allows SSH (port 8822) from specific pre-whitelisted source IPs, and the VPN's exit node was one of them; direct connections from an untrusted IP get nothing (connection times out, no rejection). Once the user's ISP/network conditions changed (~midnight China time), direct (non-VPN) transfers ran at 6–8 MB/s consistently.
- **Practical fallback used successfully**: the user relayed large files via `scp` through a second reachable box (`192.168.29.96`, the *other* reference deployment target) as an intermediate hop, then `scp`'d from there to `210.5.158.91`. When automation kept fighting the flaky link, the cleanest path was just handing the user a manifest of files+destinations and letting them copy manually — see "File categories" below.
- Takeaway for next time: **don't assume a single transfer session will complete** for anything sizable. Split large binaries into small chunks (`split -b 20m`) if a relay/manual path is being used, checksum before and after (`sha256sum`), and always use `rsync --partial --partial-dir=... --timeout=60 -e "ssh ... -o ServerAliveInterval=10 -o ServerAliveCountMax=3"` so a stalled connection is detected and the retry resumes instead of restarting.

## File categories (useful if doing this again, or for future code pushes)

**One-time / install-only:**
- ParadeDB Docker image, NATS/goose/nats binaries, Kratos static config (`kratos.yml`, `identity.schema.json`, `google_mapper.jsonnet`, `templates/`), `shared/libconfig.toml`, `config.toml`/`config.local.toml`, `.env`, `config/` (site configs), `docs/doc-templates/`.

**Per-code-change (rebuild on Mac + resync every time):**
- The 4 ChenWeb Go binaries (`server-linux`, `doc-processor-linux`, `parser-result-converter-linux`, `create-admin-linux`) — cross-compiled `GOOS=linux GOARCH=amd64 CGO_ENABLED=0`.
- `kratos-linux` — same cross-compile treatment, **not built from source on the target** (deviation from the reference doc — avoids needing Go/mise + `dl.google.com` toolchain fetch + `git clone` on a box where none of that reliably works given the network situation above).
- `project_migrations/`, `shared_migrations/` (new `.sql` files only — goose applies automatically on ChenWeb restart).
- `prompts/` (new/edited prompt files).

## Real bugs hit and fixed during this deployment

### 1. Native PG10's `btree_gin` is too old for Kratos

Ubuntu 18.04's stock PostgreSQL is 10.23. Kratos's migrations create a GIN index on a `uuid` column, which requires `btree_gin` ≥ 1.3 (UUID GIN operator class support). PG10's bundled `btree_gin` is only 1.2 — migration fails outright:
```
ERROR: data type uuid has no default operator class for access method "gin" (SQLSTATE 42704)
```
**PGDG's apt repo no longer serves `bionic` (or `focal`) at all** — `https://apt.postgresql.org/pub/repos/apt/dists/` only lists `jammy` and newer, so there's no apt-based upgrade path on Ubuntu 18.04/20.04 anymore. **Fix:** run Kratos's own Postgres as a small Docker container instead (`postgres:16-alpine`, ~110MB compressed after pulling the amd64-specific manifest digest — see the ParadeDB manifest-list gotcha below, same fix applies), on port `5434`, isolated from whatever else lives in the native PG10 instance. `pg_trgm`/`btree_gin` come pre-installable via the official image's bundled contrib.

### 2. `docker save` on a multi-arch image fails with the wrong platform pulled

`docker pull --platform linux/amd64 <image>:<tag>` on Apple Silicon, then `docker save <image>:<tag>`, fails with:
```
Error response from daemon: unable to create manifests file: NotFound: content digest sha256:... not found
```
Docker Desktop's containerd-backed image store tries to save the **full multi-platform manifest list**, including platforms never actually pulled. **Fix:** resolve the amd64-specific digest first (`docker manifest inspect <image> | jq`, find the `linux/amd64` entry), `docker pull <image>@sha256:<digest>`, `docker tag` it to a plain local name, then `docker save` *that* tag — this saves a single-platform image cleanly.

### 3. Kratos's fixed-size CORS/return-URL arrays: uniqueItems + must-fill-every-slot

`kratos.yml` declares `serve.public.cors.allowed_origins` as exactly 8 slots and `selfservice.allowed_return_urls` as exactly 13, every slot `set-via-env` (see `2026072801-devdoc-switch-app-domain-name.md` for why they're fixed-size at all). Two ways to break this:
- Leaving an env var slot unset for the *n*<sup>th</sup> index leaves the literal string `"set-via-env"` in the array, which fails schema validation (`"set-via-env" is not valid "uri"`).
- Filling remaining slots by repeating a real value (rather than a genuinely unique filler) fails `uniqueItems` validation.

**Fix:** every declared slot needs a value, and every value must be textually unique — pad unused slots with harmless-but-unique dummy URIs (`http://127.0.0.1:1`, `http://127.0.0.1:2`, …) rather than repeating a real origin.

### 4. `ChenWeb/.env`/systemd `EnvironmentFile=` formatting

Ubuntu 18.04 ships systemd 237, whose `EnvironmentFile=` parser is much stricter than a shell: no spaces around `=`, values are taken **literally** (quote characters become part of the value, they're not stripped). The Mac's `mise.local.toml`-style `KEY = "value"` formatting must be normalized to bare `KEY=value` before use as a systemd `EnvironmentFile=`.

### 5. `[config].config_filename` missing → `/api/site-config` 500s

`config.local.toml` needs an explicit `[config]` section:
```toml
[config]
config_filename = "config/site/site-default-zh-cn.toml"
```
Omitting it (easy to miss when hand-writing a fresh `config.local.toml` instead of copying the Mac's) produces `(CWB_SITE_004) [config].config_filename not set in config.local.toml` on every `/api/site-config` call, and breaks any frontend page that depends on it.

### 6. ufw allows specific trusted IPs *all ports* — don't mistake that for "it's actually public"

The box's `ufw` has both (a) a handful of explicit `ALLOW <port> Anywhere` rules (80, 443, and a few app-specific ports) and (b) a long allowlist of specific trusted source IPs with blanket access to *every* port. If your own testing machine's IP happens to be on that trusted list (as the Mac's was, `47.189.245.217` — likely left over from when this same Mac ran `dingbo.bzton.cn` directly), `curl` from that machine to *any* port will appear to succeed even if the port isn't actually open to the public. **Confirmed the hard way**: Kratos's public port (`4433`, which `SERVE_PUBLIC_BASE_URL` points browsers at directly) tested as externally reachable from the Mac, but had no explicit `ufw` rule — real visitors from arbitrary IPs would have been silently blocked, breaking login site-wide. Added `ufw allow 4433/tcp` explicitly. **Lesson: when verifying external reachability on a box with this kind of IP-allowlisting, test from a source IP that is *not* pre-trusted, or explicitly check `ufw status`/`iptables -L ufw-user-input -n -v` for a real "Anywhere" rule rather than trusting a successful curl.**

### 7. Near-miss: don't use real device paths as throwaway/placeholder command arguments

At one point a background-task retry was accidentally invoked with `/dev/null` as *both* the local source and remote destination path for an `scp` copy. `scp` (as the unprivileged `gui` user) replaced the remote `/dev/null` device node with a regular empty file (`-rw-r--r-- root:root`, 0 bytes) instead of writing harmlessly through the device — breaking `/dev/null` for **every user on the shared box** (any script/login-shell redirect that writes to `/dev/null` started failing with `Permission denied`, including `gui`'s own shell startup and even `scp` itself on subsequent connections, since sshd's session setup touches it too). **Fixed** via `rm -f /dev/null; mknod -m 666 /dev/null c 1 3; chown root:root /dev/null` (the standard major/minor for `/dev/null` on Linux). Root cause: a placeholder/test command using `/dev/null /dev/null` as dummy args to a script that does a real `scp`. **Never use a live device path as a disposable test argument — use an actual scratch file.**

### 8. Multi-file `rsync`/`scp` transfers to this box fail; single files (including tarballs) don't

Discovered while transferring `pdf-parser`'s source tree (24 small files, 728K total): `rsync -avz` of a *directory* consistently failed 10/10 times with `unexpected end of file` / `rsync error: rsync_sender` right after `Transfer starting: N files` — every retry died at the exact same point. A single-file transfer of comparable or larger size (`README.md`, then a 65MB tarball) worked immediately at full speed. Something about this box's connection (likely DPI/firewall behavior specific to rsync's multi-file protocol chatter, not just raw throughput) kills multi-file rsync sessions specifically. **Fix / standing rule for this box: always `tar czf x.tar.gz dir/` locally and transfer the single tarball, then `tar xzf` on the target — never rsync a directory with more than one file directly.**

### 9. `uv pip install`/`uv sync` only links packages into `site-packages` at the very end

A run that gets killed or interrupted mid-install (connection drop, manual `kill`, session timeout) can show pages of `Downloading X` / ` Downloaded X` progress and still leave **nothing** actually installed — `uv` downloads and builds everything first, then does the "link into venv" step as a fast final batch (`Installed N packages in Nms`). **Always verify via `ls .venv/lib/python3.12/site-packages/` (or check for the specific binary/module) rather than trusting `Downloading`-line progress as a sign anything is usable yet.** This cost significant time early in the `mineru` install — hours of apparent progress across several killed/restarted attempts had actually installed nothing beyond a single explicitly-completed `numpy` install.

### 10. Non-detached remote commands get killed when the monitoring SSH session eventually closes

Several long-running installs (`uv pip install -e '.[pipeline,api]'`, `uv pip install torch ...`) were launched as plain foreground commands over an interactive `ssh`/`expect` session (no `nohup`, no `disown`). They kept running for a while after the checking command returned (sometimes 10+ minutes), then died with no error — the underlying TCP session finally closing took the process with it. **Standing rule for this box: any command that might take longer than ~30–60 seconds must be launched as `nohup <cmd> > logfile 2>&1 & disown`, and progress must be checked via the logfile + `ps aux`, never assumed from a foreground command's return.**

### 11. `mirrors.aliyun.com/pypi/simple/` is dramatically faster/more reliable than `files.pythonhosted.org` direct — but don't mix it with the PyTorch CPU index

Direct downloads from `files.pythonhosted.org` (PyPI's own CDN) stalled unpredictably and repeatedly on this box — the same package (e.g. `numpy`, `psycopg2-binary`) that hung for 10+ minutes via the default index installed in under 2 seconds via `--index-url https://mirrors.aliyun.com/pypi/simple/` (the same mirror already confirmed fast for `apt`). **Use it for everything** — except:
- **`torch`/`torchvision` must be installed with *only* `--index-url https://download.pytorch.org/whl/cpu` and no `--extra-index-url` at all.** Adding the Aliyun mirror (or any general PyPI mirror) as an extra index lets `uv`'s resolver pick a *newer* version of `torch` from the general index (which defaults to the CUDA-enabled build, ~731MB torch + ~2GB of `nvidia-*-cu12` packages neither wanted nor usable on a CPU-only box) instead of reusing the already-installed CPU-only wheel. Install `torch`/`torchvision` alone first (CPU index only), confirm `torch==X+cpu` / `torchvision==X+cpu` in `pip list`, *then* run the main package install with the Aliyun mirror as `--extra-index-url` — by then torch/torchvision are already satisfied and the resolver won't touch them.

### 12. `av` (PyAV) and `pymupdf`: Ubuntu 18.04 is too old for the packages' current wheels/source builds

Both are real platform-floor problems on Ubuntu 18.04 (glibc 2.27, system FFmpeg 3.4.11):
- **`av`**: `mineru` → `qwen-vl-utils` → `av==18.0.0` fails to build from source (`pkg-config could not find libraries ['avformat', 'avcodec', ...]`) until FFmpeg dev headers are installed (`sudo apt install -y pkg-config libavformat-dev libavcodec-dev libavdevice-dev libavutil-dev libavfilter-dev libswscale-dev libswresample-dev`) — but even then, the source build fails differently (`AVCodecParameters' has no member named 'ch_layout'`) because system FFmpeg 3.4 predates the channel-layout API `av` 18.x's C extension expects. **Fix:** force a prebuilt wheel instead of a source build — `uv pip install av --only-binary av` resolves to `av==14.2.0` (which does publish a compatible wheel) rather than 18.0.0 (which doesn't, for this platform). Once installed, the main `mineru` install command picks it up as already-satisfied.
- **`pymupdf`** (imported as `fitz`, a direct `pdf-parser` dependency, `>=1.24`): versions ≥1.26.1 only publish `manylinux_2_28` wheels (glibc ≥2.28); Ubuntu 18.04 has glibc 2.27 — one version short. `uv pip install pymupdf --only-binary pymupdf` correctly refuses (`has no usable wheels`) rather than silently building from source; the default (unconstrained) resolution instead falls through to building `pymupdf==1.27.2.2` from source, which then hangs indefinitely trying to download MuPDF's C source bundle from a GitHub CDN edge (`cdn-185-199-109-133.github.com`) — the same GitHub-hosted-content unreliability seen elsewhere this session. **Fix:** `1.26.0` is the newest version still publishing a `manylinux2014`/`manylinux_2_17` wheel (glibc 2.17 floor) — `uv pip install 'pymupdf==1.26.0' --only-binary pymupdf` installs cleanly in seconds. This still satisfies `pdf-parser`'s own `>=1.24` constraint.

### 13. `pdf-parser`'s `uv sync` pulls in ~150 unneeded packages (opencv, scipy, pandas, paddleocr, torch's CUDA cousins via other extras) that aren't actually needed for the `mineru` backend

`pdf_parser.py` imports every parser backend module (`parser_docling`, `parser_paddle`, `parser_opendata`, `parser_mineru`) unconditionally at the top of the file — but `parser_docling.py`/`parser_paddle.py` only `import importlib` at module level and lazy-load their real (heavy) dependencies (`docling`, `paddleocr`) *inside* functions, only when that specific backend is actually invoked. Since this deployment only ever runs with `PDF_PARSER_NAME=mineru` (which shells out to the separate `ThirdParty/mineru` CLI as a subprocess, not a Python import), the full `uv sync` (161 packages, pulling in the `paddle` extras group) is unnecessary. **What's actually needed:** `uv pip install -e .` (no extras) — just 9 packages (`nats-py`, `psycopg2-binary`, `pymupdf`, plus `pdf-parser`'s own dev deps). Verified via `python -c 'import pdf_parser'` succeeding with only the minimal set installed. If a different backend (`paddle`, `docling`) is ever actually enabled here, its extras group and full dependency tree would need installing at that point.

## Current deployed state (as of 2026-07-31)

- **Services** (all systemd-managed, `enabled` + `active`, 0 restarts): `nats-server` (4222), `kratos` (4433 public / 4434 admin, own `kratos-postgres` Docker container on 5434), `chenweb` (8080, loopback-only), `doc-processor`, `parser-result-converter`, `pdf-parser` (JetStream consumer, `PDF_PARSER_NAME=mineru`, no HTTP port). `chenweb-paradedb` Docker container (ParadeDB, `pg_search`+`vector` confirmed) on 5433, loopback-only.
- **MinerU**: `ThirdParty/mineru` built from source-transferred tarball (not `git clone` — see network notes), own venv (Python 3.12 via `uv python install`, not the box's stale system `uv 0.1.32` at `/usr/local/bin` — a fresh `uv` was installed to `~/.local/bin`), CLI verified working (`mineru --version` → `3.0.9`). Pipeline model weights (2.5GB+, `opendatalab/PDF-Extract-Kit-1.0`) copied directly box-to-box from `192.168.29.96` (which already had them from the reference deployment) rather than via the Mac — much faster, and sidesteps HuggingFace being blocked from China entirely. `mineru.json` at `~/Workspace/mineru.json` points `models-dir.pipeline` at the transferred snapshot dir.
- **nginx**: new vhost `/etc/nginx/conf.d/dingbo-bzton-cn.conf`, `dingbo.bzton.cn:80` → `127.0.0.1:8080`.
- **ufw**: added explicit `4433/tcp ALLOW Anywhere` (both v4/v6) for Kratos's public API, alongside the pre-existing `80`/`443` Anywhere rules.
- **Sysadmin account**: `admin@dingbo.bzton.cn`, `metadata_public: {"admin": true, "roles": ["admin"]}` confirmed via Kratos Admin API.
- **Auth**: password login only. Google OAuth credentials are carried over from the Mac's config for parity but the redirect URI for this host isn't registered in Google Cloud Console yet — Google login will not work until that's added. SMTP is a non-sending placeholder (no real outbound email yet).

## Still pending / handoff

- **DNS cutover**: `dingbo.bzton.cn` still resolved to the MacMini's old IP (`47.189.245.217`) as of this deployment — the user owns DNS and will cut it over on their own schedule (may be after this session).
- **TLS cert**, once DNS points here:
  ```bash
  sudo apt install -y certbot python3-certbot-nginx
  sudo certbot --nginx -d dingbo.bzton.cn
  ```
  After the cert is live, also flip `SESSION_COOKIE_SECURE=true` in `Kratos/kratos.env` and switch the `http://` URLs in `ChenWeb/.env` / `Kratos/kratos.env` to `https://`, then restart both services.
- **Google OAuth**: register `http://dingbo.bzton.cn:4433/self-service/methods/oidc/callback/google` (and the eventual `https://` version) as an Authorized redirect URI in Google Cloud Console before Google login will work here.
- **`pdf-parser` end-to-end test**: the service is up and subscribed to JetStream, but hasn't yet been exercised against a real PDF — worth staging a test document through `kb.pdf.staged` and confirming `mineru` actually produces output before relying on it in production.

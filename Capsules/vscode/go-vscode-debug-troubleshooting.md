# Go / VS Code Debug Troubleshooting

This document records two related bugs that broke VS Code debugging in this project and explains how to fix them if they recur. Both bugs stem from Go version conflicts made worse by the mix of Nix, Nix flakes, direnv, and mise managing Go installations.

---

## Environment overview

This project uses **three** Go version managers simultaneously:

| Manager | Config | Primary role |
|---|---|---|
| **home-manager (Nix)** | `~/Workspace/nix/` flake | System-level Go in `/etc/profiles/per-user/cding/bin/go` |
| **mise** | `ChenWeb/mise.toml`, subdirectory `mise.toml` files | Per-directory Go pins (e.g. `go = "1.25.7"` in `cmd/doc-processor/`) |
| **Nix flake (ChenWeb)** | `ChenWeb/flake.nix` + `.envrc` (`use flake`) | devShell tools loaded by direnv |

VS Code's Go extension is configured via:
- `go.goroot` → Nix home-manager Go path  
- `go.alternateTools.go` → `/etc/profiles/per-user/cding/bin/go`

---

## Bug 1: Go toolchain version mismatch

### Error message

```
Build Error: go build -o __debug_bin... -gcflags all=-N -l .
# internal/profilerecord
compile: version "go1.25.7" does not match go tool version "go1.25.0"
```

### What it means

The `go` driver binary is version 1.25.0, but it is finding a `compile` binary from Go 1.25.7 (via GOROOT or PATH). Go's compiler and driver must come from the same installation.

### Root cause: Nix flake injecting a conflicting Go via direnv

`ChenWeb/.envrc` runs `use flake`, which activates `ChenWeb/flake.nix`. The flake's `devShells.default` previously listed `go` as a package:

```nix
packages = with pkgs; [
  go          # ← pkgs.go from nixpkgs-unstable = Go 1.25.0 at time of bug
  bun
  just
  ...
];
```

When direnv loads (automatically in VS Code via the direnv extension), it prepends the flake's Go 1.25.0 to PATH. Meanwhile `go.goroot` in VS Code points at Go 1.25.7, so the 1.25.0 `go` driver ends up looking for `compile` in the 1.25.7 GOROOT. Mismatch.

**Secondary cause: stale downloaded toolchains**

Go's `GOTOOLCHAIN=auto` (the default) can auto-download toolchains into `$GOMODCACHE/golang.org/toolchain@v0.0.1-goX.Y.Z.darwin-arm64/`. These can also end up mixed in if any path lookup finds them first.

> **Nix note:** `GOMODCACHE` is `~/.local/share/go/pkg/mod`, **not** `~/go/pkg/mod`. If you try to clean the toolchain cache, clean the right path.

### Fix

**Step 1 — Remove `go` from the flake** (permanent fix):

In `ChenWeb/flake.nix`, remove `go` from the devShell packages. Go is already managed by home-manager and mise; the flake does not need to provide it.

```nix
packages = with pkgs; [
  # go  ← removed; managed by home-manager + mise
  bun
  just
  nodejs_24
  golangci-lint
];
```

Then reload direnv (VS Code will pick it up on next window reload, or run `direnv reload` in a terminal inside the ChenWeb folder).

**Step 2 — Prevent toolchain auto-download** (one-time):

```bash
go env -w GOTOOLCHAIN=local
```

This writes to `~/.config/go/env` and is respected by every `go` invocation regardless of how it is launched. `local` means: always use whichever Go is active; never auto-download a different version.

**Step 3 — Clean any stale toolchain downloads** (if needed):

```bash
chmod -R u+w ~/.local/share/go/pkg/mod/golang.org/toolchain@*
rm -rf ~/.local/share/go/pkg/mod/golang.org/toolchain@*
rm -rf ~/.local/share/go/pkg/mod/cache/download/golang.org/toolchain
```

### How to detect recurrence

- `go env GOTOOLCHAIN` should return `local`.
- `cd ChenWeb && direnv exec . go version` should return the home-manager Go version.
- No `toolchain@*` directories should appear in `~/.local/share/go/pkg/mod/golang.org/`.

---

## Bug 2: dlv DAP reverse-mode timeout

### Error message

```
Failed to launch dlv: Error: timed out while waiting for DAP in reverse mode to connect
```

### What it means

When `"console": "integratedTerminal"` is set in `launch.json`, VS Code's Go debug adapter launches `dlv` in **reverse-mode DAP**: VS Code listens on a port and waits for `dlv` to connect back. If the terminal's shell startup takes too long (zsh + mise activation + optional direnv), `dlv` does not connect within the timeout window.

### Root cause

`ChenWeb/.vscode/launch.json` had:

```json
"console": "integratedTerminal"
```

The `cmd/doc-processor/` directory has a `mise.toml` that activates Go tools. Every new integrated terminal triggers full mise activation before `dlv` even starts.

### Fix

Remove `"console": "integratedTerminal"` from the launch configuration. The debug output goes to VS Code's Debug Console panel instead (fine for a server process that does not need terminal stdin).

```json
{
  "name": "Doc Processor",
  "type": "go",
  "request": "launch",
  "mode": "auto",
  "program": "${workspaceFolder}/server/cmd/doc-processor",
  "cwd": "${workspaceFolder}/server/cmd/doc-processor",
  "envFile": "${workspaceFolder}/server/cmd/doc-processor/.env",
  "env": {
    "DOC_PROCESSOR_CONFIG": "${workspaceFolder}/config.toml",
    "MODELS_FILE": "${workspaceFolder}/.models.toml",
    "SHARED_LIB_CONFIG_DIR": "${workspaceFolder}/../shared/libconfig.toml"
  }
}
```

> If a future configuration genuinely needs the integrated terminal (e.g., the program reads from stdin), use `"dlvFlags": ["--init-timeout=120s"]` instead of removing `"console"`.

---

## Why Nix makes this harder

1. **Multiple Go installations coexist** in the Nix store. A single `find / -name go -type f` may return 5+ valid Go binaries at different versions, all in `/nix/store/...`.

2. **direnv + `use flake` silently prepends to PATH.** The flake's devShell packages take precedence over everything mise or home-manager provides for processes launched in that environment (including VS Code's language server and debug adapter processes).

3. **VS Code inherits a bare PATH from macOS launchd** (`/usr/bin:/bin:/usr/sbin:/sbin`). It does not inherit your shell's mise/Nix PATH. Go resolution inside VS Code depends entirely on `go.alternateTools`, `go.goroot`, and whatever direnv injects.

4. **GOMODCACHE is not `~/go/pkg/mod`** when mise manages Go. Mise sets `GOPATH=~/.local/share/go`, so module cache is at `~/.local/share/go/pkg/mod`. Cleaning the wrong path has no effect.

5. **`go env -w` writes to `~/.config/go/env`**, which every `go` binary reads on startup regardless of installation path. This is the most reliable way to set persistent Go env vars across all Nix/mise-managed versions.

---

## Quick diagnostic checklist

When debugging fails with a version mismatch or dlv timeout, run these:

```bash
# 1. What Go does VS Code's direnv-loaded environment see?
cd ~/Workspace/ChenWeb && direnv exec . go version

# 2. Is GOTOOLCHAIN set to prevent auto-downloads?
go env GOTOOLCHAIN   # should be "local"

# 3. Are there stale downloaded toolchains?
ls ~/.local/share/go/pkg/mod/golang.org/   # should be empty or contain only "x/"

# 4. What Go does mise resolve in the debug directory?
cd ~/Workspace/ChenWeb/server/cmd/doc-processor && mise exec -- go version

# 5. Does a clean build work from the terminal?
cd ~/Workspace/ChenWeb/server/cmd/doc-processor && go build .
```

All five should agree on **Go 1.25.7** (or whatever home-manager currently pins).

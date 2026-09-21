# Incident: `config.toml` Drift Silently Overrode `config.local.toml` on the China Box

**Date:** 2026-09-23
**Scope:** Root-cause writeup for why an `extract_products` doc-processing request kept
being skipped on `onto.bzton.cn` (210.5.158.91) even after `config.local.toml` was
correctly edited to include it, and the fix applied to `mise.toml` / `scripts/deploy-server-china.sh`
in ChenWeb so this class of drift is caught by the routine deploy path going forward.

## Symptom

Running `extract_products` only against `record_id=1` on the box logged:

```
INFO doc processor skipped, no matching operation
  requested="[extract_products]"
  allowed="[static_analyzer chunking extract_doc_metadata generate_topics
            extract_semantic_projections extract_entity extract_relation
            extract_inventory_items extract_metrics extract_provisions
            generate_scene_blocks]"
```

The box's `~/Workspace/ChenWeb/config.local.toml` already had `extract_products` added to
`[doc-processing] required_processors`, and `doc-processor` had been restarted (confirmed via
`systemctl show -p ExecMainStartTimestamp` — a genuinely fresh process, not a stale one).

## Root cause

Two independent problems stacked:

1. **The box's `config.toml` (git-tracked, not `.local.`) was stale.** Commit `f26af3cc`
   ("feat: add processor package selector", 2026-09-17) removed the `[doc-processing]`
   section from the repo's `config.toml` entirely, moving processor selection to live only
   in `config.local.toml`. The China box's `config.toml` predates that commit and still had
   the old 8-processor `required_processors` list (pre-`extract_products`).

2. **That stale leftover wasn't inert — it won.** `configuredNames()`
   (`server/api/doc-processing/runtime.go:377-383`) and `configuredProcessorNames()`
   (`server/cmd/doc-processor/main.go:128-130`) both do:
   ```go
   func configuredNames() []string {
       if names := viper.GetStringSlice("doc-processing.required_processors"); len(names) > 0 {
           return names   // reads the GLOBAL default viper singleton
       }
       required, _ := appconfig.GetDocProcessingProcessors()  // the correctly-merged one
       return required
   }
   ```
   The first branch reads the **global default `viper` singleton**, which
   `shared/go/api/ApiUtils/ApiUtils.go:949` populates by reading `config.toml` alone
   (`viper.SetConfigFile` + `viper.ReadInConfig` on the package-level instance — **no**
   `config.local.toml` merge). `server/cmd/config/config.go`'s own `LoadConfig` does the
   correct merge (`config.toml` then `config.local.toml` override) but into its own private
   `appVp`/`appConfigViper` instance — a *different* viper instance from the global one.
   Whenever the box's `config.toml` still defines `required_processors` at all, the global
   singleton's non-empty value short-circuits `configuredNames()` before the correctly-merged
   `config.local.toml` override is ever consulted.

   This is why it worked on the Mac (root `config.toml` there has no `[doc-processing]`
   section post-2026-09-17, so the first branch returns empty and correctly falls through)
   but silently broke on any box whose `config.toml` wasn't re-synced past that commit.

Confirmed by extracting both the box's `config.toml` and `config.local.toml` and replaying
the exact `viper`/`go-toml` merge with the pinned versions (`spf13/viper v1.21.0`,
`pelletier/go-toml/v2 v2.2.4`) — the merge itself is correct; the bug is that
`configuredNames()` doesn't use the merged result when the global singleton already has a
non-empty answer.

## Why `config.toml` drifted in the first place

`config.toml` was never part of the *routine* deploy path. The one-time bring-up runbook
(`2026072401-devdoc-deploy-production.md` §2.3) does `rsync config.toml`, but the script used
for every subsequent binary push (`scripts/deploy-server-china.sh`, driven by
`mise build-server-linux`) only ever staged binaries + migrations + `prompts/` +
`doc-review.local.toml`/`product-review.local.toml`. `config.toml` (and the `config/` tree,
and `docs/doc-templates/`) were git-tracked, deployment-relevant, non-code files with no
mechanism keeping them in sync after the initial bring-up.

A broader audit of ChenWeb's git-tracked non-code files (same session) found `config/` and
`product-review.local.toml` were, by luck, already current on this box — but nothing was
actually enforcing that; it happened to not have drifted yet.

## Fix

1. **Immediate, on the box:** remove the stale `[doc-processing]` block from
   `~/Workspace/ChenWeb/config.toml` (or re-rsync the current repo copy), then
   `systemctl restart doc-processor`.
2. **Structural, in the repo (ChenWeb jj, 2026-09-23):**
   - `mise.toml`'s `build-server-linux` task now also stages `config.toml`, the full
     `config/` tree, and `docs/doc-templates/` into the `/tmp/chenweb-deploy` payload,
     alongside migrations/prompts/reviewer configs. Recorded in the payload's `MANIFEST`.
   - `scripts/deploy-server-china.sh` now installs `config.toml` (only if it differs from
     the box's copy) and mirrors `config/` + `docs/doc-templates/` (with `--delete`, same
     policy as `prompts/`) on every run, regardless of which binaries are named on the
     command line.
   - `2026072401-devdoc-deploy-production.md` §2.3 updated to note the China-box path no
     longer needs those two rsync lines run by hand; they still apply as-is for a brand-new
     box or the original Mac Mini target.

**Not yet fixed:** the underlying `configuredNames()`/`configuredProcessorNames()` global-vs-
merged-viper-instance bug in `server/api/doc-processing/runtime.go` and
`server/cmd/doc-processor/main.go` still exists in source. It's dormant as long as no
`config.toml` on any box ever redefines `doc-processing.required_processors` (true today,
now that the deploy script keeps `config.toml` in sync), but it would resurface the moment
`config.toml` and `config.local.toml` both define that key again on some box. Worth a real
source fix (drop the `viper.GetStringSlice(...)` global-singleton fallback and call
`appconfig.GetDocProcessingProcessors()` unconditionally) — deferred, not done in this pass.

## See also

- `2026090701-devdoc-start-system-onto.md` §6.2 — the same "`.local.`-named file is actually
  git-tracked and easy to leave out of a deploy" pattern, for `doc-review.local.toml`.
- `project_util_tools_toolbox` / workspace `CLAUDE.md` — general non-code-file deployment
  discipline this incident prompted a review of.

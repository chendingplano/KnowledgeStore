# New Gold Metrics button — design record for a not-yet-built feature

**Date:** 2026-10-15 \
**Scope:** Records the agreed shape of a "New Gold Metrics" button on the Gold Metrics page, what was learned while scoping it, and the one decision still open. Open it when you are ready to build the feature.
**Code root:** `ChenWeb/web/src/lib/components/home3/` (UI), `ChenWeb/server/api/kbhandler/` (server)
**Status:** NOT IMPLEMENTED. Nothing was changed in code. This is a record of a request that was scoped, then deliberately postponed by the owner on 2026-10-14. Unlike most devdocs it describes intent, not shipped behavior; rewrite it as current behavior once the feature exists.

## Summary

The Gold Metrics page (System Admin → LLM → Metrics → Gold Metrics) lets you browse
"gold" benchmarks: carefully checked lists of the metrics a document really contains,
used to score the automatic extractor. Today a gold benchmark can only be produced by
running an AI agent by hand in a terminal, using the `extract-metrics-benchmark` skill.

The request is to add a **New Gold Metrics** button next to "Close panel". Pressing it
shows a form in the big empty area (the one that normally says "Awaiting selection"):
pick a document, pick a model, pick a version of the benchmark rules (newest by
default), then press **Create** to start building the benchmark, **Cancel** to leave,
or **Help** to read what the form does.

The hard part is not the form. Creating a gold benchmark is a long, multi-step agent
job (read the whole document, annotate, audit, validate, save), and the web server has
no way to run such a job today. That choice is still open (see "Open decision").

## Details

### Requested behavior

| Item | Requirement |
|---|---|
| Button | "New Gold Metrics", placed immediately before "Close panel" in the page header strip. Label via Paraglide (`m.*()`), keys in both `web/messages/en.json` and `zh-cn.json`. |
| Where the form appears | Replaces the "Awaiting selection" placeholder (`inputs_mgmt_awaiting_selection`) in the right-hand pane while the form is open. |
| Document | Search for one `kb.inputs` record. Reuse the existing record search/browser rather than building another (`kb-input-record-browser.svelte`). |
| Model | Pulldown. Source of options is open (see below). |
| Skill version | Pulldown of the released rules versions, default = newest. |
| Buttons | Cancel (closes form), Create, Help (explains the form). |
| Create | Runs `extract-metrics-benchmark` with the chosen version and model on the chosen record, producing a saved run in `testbed.metrics`. |

### What already exists (verified 2026-10-14)

- Header buttons: "Hide header" and "Close panel" (`content_panel_close_panel`) are
  rendered by `content-panel.svelte`; the page is `MetricMgmtView` with `source="testbed"`
  for menu id `sysadmin-llm-metrics-gold`.
- Version list: `.agents/skills/extract-metrics-benchmark/rules/versions.json` lists every
  released version. "Newest" means highest version compared numerically (pre-releases such
  as `2.0.0-rc.1` only if named). Server helpers `compareSkillVersions`,
  `sortSkillVersionsDesc` and `newestGoldSkillVersion` in `kbhandler/gold_metrics_options.go`
  already do this ordering for saved runs; they read the database, not `versions.json`, so a
  version with no saved run would not show up. A "create" form needs the file-based list.
- Existing endpoints: `GET /kb/metrics/gold-options`, `GET /kb/metrics/gold-runs`-style
  listing, and the scorer under `/kb/metric-scores` (registered in `server/api/routes.go`).
- The only server-side skill-like runner is `kbhandler/metric_score_runner.go`. It runs
  the **scoring** skill: a Python helper exports data, one LLM call does the matching,
  the helper scores. It is a single call, not an agent, so it cannot create a benchmark.
- "Chad Sessions" / "Pi Sessions" in System Admin are read-only viewers of agent sessions
  (`server/api/chadsessionshandler/`); they do not launch anything.
- The skill itself is marked `disable-model-invocation` and is normally triggered by the
  prompt: `Use $extract-metrics-benchmark, version <version> for document <id>`. That prompt
  authorizes the full run including the save; the skill refuses to overwrite an existing run
  key (skill name, version, model, run id).
- `claude`, `codex`, `pi` and `gemini` CLIs are installed on this machine (`~/.cache/.bun/bin`).
  Existing gold runs carry model names such as `claude-opus-5-5` and `gpt-6.1-sol`, so they
  were produced by agent CLIs, not by the app's API model profiles.

### Open decision: how "Create" runs the skill

| Option | What it means | Trade-off |
|---|---|---|
| **A. Spawn an agent CLI (leaning choice)** | Server starts a headless `claude` or `codex` process with the skill prompt and the chosen model, as a background job. UI polls status/log. | Matches how runs are made today. Needs job tracking, a log, cancel, and a model→CLI mapping. Server host needs the CLI and credentials. |
| B. Copy command only | Create validates and shows the exact prompt/command to paste in a terminal. | Trivial and safe, but the form creates nothing by itself. |
| C. Re-implement in Go | Rebuild the skill as a server LLM pipeline on the app's model profiles. | Large, and duplicates the versioned rules files. Not recommended. |

The owner did not choose between these before postponing. Decide this first.

### If option A is chosen, things to settle in design

- **Model list:** a fixed server-config list of agent models, each mapped to the CLI that
  runs it (matches existing run model names), versus reusing the app's LLM model profiles
  (these are API profiles and may not map to a CLI). A fixed list is the safer fit.
- **Job lifecycle:** a job record (state, start/end, record id, version, model, log path),
  status endpoint, cancel, one-job-per-(record, version, model) guard so it cannot collide
  with the skill's own "run key already saved" refusal.
- **Credentials:** the skill reads the database via `PG*` environment variables. Follow
  `metricScoreCommandEnv()` in `metric_score_runner.go` (pool config, no passwords in argv).
- **Permissions:** an agent that can write to the database and read files is powerful.
  Restrict to System Admin, and decide the CLI's tool/permission mode explicitly.
- **Result:** when the job ends, the page should refresh its run list and select the new run.
  Success means the skill's own read-back checks passed; surface its report, not just exit code.
- **Help text:** explain that a run is long, costs model usage, and cannot overwrite an
  earlier run.
- **Process:** per `ChenWeb/CLAUDE.md` and project convention, build it as an OpenSpec
  change (`openspec/changes/<name>/`), then update this devdoc to the OpenSpec template.
- **Frontend rules:** the new form root needs `select-text` (the dashboard main area sets
  `select-none`); all text through Paraglide; verify with `bun run check` from `web/`.

## Known limitations

- This document describes a feature that does not exist yet; every "requirement" above is
  intent, and the "What already exists" section was verified only on 2026-10-14.
- Until the feature is built, gold benchmarks are created only by invoking the skill
  manually in an agent terminal.

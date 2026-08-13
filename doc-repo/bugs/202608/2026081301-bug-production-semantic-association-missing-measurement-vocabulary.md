# Production ontology bootstrap never ran: curated modules missing from `miner`

Date: 2026-08-13

Status: open

System: `ChenWeb` document processing / SemOS ontology

Component: `ontology-seed`, `associate_semantics`, production database bootstrap

Related: [metric assertion and semantic processing manual](../user-manuals/metric-assertion-semantic-processing-v1.1-en.md),
`ChenWeb/server/api/ontology/assertions/associate_semantics.go`,
`ChenWeb/server/cmd/ontology-seed/main.go`,
`ChenWeb/server/cmd/doc-processor/main.go`

## Summary

Running `associate_semantics` for input record 416 in the production `miner`
database produced no rows in `kb.semantic_assertions` or
`kb.assertion_evidence` for that record.

The normal command paths are using the correct database:

- `mise dev` in `ChenWeb` resolves `PG_DB_NAME=miner`.
- `mise doc-process-run` in `ChenWeb/server/cmd/doc-processor` resolves
  `PG_DB_NAME=miner`.
- `chenweb_test` is selected by benchmark/test tooling, not by these normal
  service commands.

There are **two independent causes**, and they must not be conflated:

1. **Production ontology bootstrap never ran.** `miner` contains neither the
   curated `measurement` module nor the curated `document-authority` module.
   This blocks 3 of record 416's candidates.
2. **No governed deontic predicate exists in any module.** `processProvision`
   defers every provision candidate unconditionally, before consulting the
   ontology at all. This blocks 89 candidates and is a code/content gap that
   no amount of seeding fixes.

The original framing of this bug attributed the whole zero-assertion result to
cause 1. That is wrong by two orders of magnitude: bootstrapping `measurement`
unblocks 3 of 155 candidates.

## Expected behavior

The documented path is:

```text
extract_metrics
    -> kb.metrics
    -> metric identity resolution
    -> metric_definition_term_id
    -> normalize_assertions
    -> kb.semantic_decision_candidates
    -> associate_semantics
    -> kb.semantic_assertions + kb.assertion_evidence
```

For a parseable metric candidate with a resolved subject, `associate_semantics`
should accept the claim when the governed measurement terms are available.

## Actual behavior

For input record 416 in `miner`:

| Result | Count |
|---|---:|
| `kb.metrics` rows | 66 |
| decision candidates (live) | 155 |
| accepted semantic assertions | 0 |
| evidence rows | 0 |

Candidates by source artifact type and status:

| Source artifact type | Status | Count |
|---|---|---:|
| `metric` | `deferred` | 66 |
| `provision` | `deferred` | 89 |
| `provision` | `superseded` | 26 |

Deferral reasons (`dependency_fingerprint`):

| Deferral reason | Count | Cause |
|---|---:|---|
| `no_governed_deontic_predicate` | 89 | code gap (unconditional) |
| `no_governed_assertion_kind_term:unparsed` | 37 | value not parseable |
| `unresolved_referent` | 20 | subject not reconciled |
| `no_governed_assertion_kind_term:exact_value` | 6 | assertion kind not seeded |
| `governed_term_not_released:mea:measured_by,mea:lower_bound_requirement` | 3 | **missing bootstrap** |

Only the last row is caused by the missing `measurement` release.

`kb.semantic_assertions` is **not** globally empty: it holds 122 rows, all with
`predicate_term_id = 'core:aligns_to_term'`, written by the keyword alignment
path. The assertion and evidence write path itself is functional in production.
The zero count above is scoped to record 416.

Note for anyone reproducing these numbers: `kb.semantic_assertions` has no
`input_record_id` column. Per-record scoping goes through
`kb.assertion_evidence`. The candidate-side query is:

```sql
SELECT source_artifact_type, status, dependency_fingerprint, count(*)
FROM kb.semantic_decision_candidates
WHERE input_record_id = 416
GROUP BY 1, 2, 3 ORDER BY 4 DESC;
```

## Database evidence

Verified state of `miner` on 2026-08-13:

```text
kb.ontology_modules:
  core
  quantity
  (document-authority MISSING)
  (measurement MISSING)

kb.ontology_module_releases:
  core@1.0.0       (not superseded)
  quantity@1.0.0   (not superseded)

kb.ontology_terms by module and status:
  core         included_in_release    20
  quantity     included_in_release  4213
  measurement  auto-promoted         122

kb.ontology_terms WHERE term_id LIKE 'mea:%':  0 rows
```

The association code checks for `mea:measured_by` and
`mea:lower_bound_requirement` with `status = 'included_in_release'`
(`associate_semantics.go` `termExists`). Neither term exists in `miner`.

The `measurement:auto:kwc_*` terms attached to the 416 metrics are different
records. They are metric-definition identities created by the metric-name
resolution path, carrying `status = 'auto-promoted'`. They do not create the
assertion predicate or assertion-kind vocabulary.

Their presence does **not** contaminate a future release. `buildSnapshot`
(`modules/validate.go`) selects only `status = 'approved'` terms, so releasing
`measurement@1.0.0` will snapshot the ~19 curated `mea:*` terms and leave all
122 auto-promoted terms untouched. This is worth stating explicitly because it
is the obvious concern when releasing a module that already has terms in it.

`quantity` has 4213 released terms, so `measurement`'s dependency pin
(`DependsOn: core, quantity`) will resolve successfully today.

## Root cause

### Cause 1: ontology bootstrap is a manual, out-of-band step

1. `ontology-seed` is a standalone command run by neither `mise dev` (the
   `deepdoc` backend) nor `mise doc-process-run` (the `doc-processor` service).
2. Database migrations create the ontology tables but never install curated
   module content.
3. The production database was therefore never seeded or released.
4. `ontology-seed` has an inconsistent environment contract: it reads
   `PG_USER`, while `mise.local.toml` defines `PG_USER_NAME`. It also defaults
   `PG_DB_NAME` to `chenweb_test` when the variable is absent.
5. The `mise run ontology-compiler` task explicitly exports
   `PG_DB_NAME=chenweb_test`, making it unsafe as a production bootstrap path.

This is not caused by the normal services connecting to `chenweb_test`, and it
is not caused by the `auto-promoted` status of the metric-definition terms.
`auto-promoted` terms are intended to be usable metric identities. The
association gate is a separate check for released curated predicate and
assertion-kind terms.

### Cause 2: no governed deontic predicate term exists

`processProvision` (`associate_semantics.go`) resolves nothing and defers every
provision candidate with `no_governed_deontic_predicate`, unconditionally,
before any ontology lookup. The curated `core` module contains no
required/prohibited/permitted predicate term to reference. This is documented
in the code as a known content gap.

This is the largest blocker for record 416 (89 candidates) and is untouched by
any bootstrap work. It needs its own tracked item and its own owner.

## The bootstrap belongs in the pipeline, not in an operator's hands

`ontology-seed` should not be a manual step, and the "do not run it silently on
every startup" caution in the original writeup drew the line in the wrong
place. The distinction that matters is content provenance, not run frequency:

- **Curated, platform-owned content** lives in `server/cmd/ontology-seed/content.go`,
  is compiled into the binary, and changes only when a developer edits Go
  source and passes code review. Its governance *is* code review plus the
  version constant in `content.go`. Installing it is the data analogue of a
  schema migration.
- **Proposed content** (`kb.ontology_candidates`, applicability proposals,
  auto-promoted terms) is what the review/release policy exists to govern.
  `ontology-seed` never touches it.

So auto-installing curated content at startup does not bypass governance.

### It is not a service, and not a doc processor

- **Not a service.** It is a one-shot idempotent bootstrap over ~19 terms that
  completes in milliseconds. Nothing to supervise, nothing to keep resident.
- **Not a doc-processor step.** It has no input record, no per-document work,
  and creating an ontology *release* once per processed document would be
  wrong: a release is a governance event, not per-document work.
- **It is a startup precondition** — a function call, exactly as suspected.

### Recommended shape

Expose an idempotent `EnsureCuratedModules(ctx, db)` from a package importable
by both binaries, and call it at startup immediately after `RunMigrations`:

- `server/cmd/deepdoc/main.go`, after the `RunMigrations` block (~line 194).
- `server/cmd/doc-processor/main.go`, after `RunMigrations` (~line 230),
  directly alongside the existing `ensureLLMUsageSink()` call — which is
  already precisely this pattern: an idempotent "ensure required state exists"
  startup step that exits non-zero on failure.

Both binaries need it independently: `doc-processor` runs `associate_semantics`,
and `deepdoc` serves the `/kb/ontology` APIs. Idempotency makes double-running
harmless.

`server/cmd/ontology-seed` then becomes a thin wrapper over the same function,
retained for one-off operator use and for seeding test databases — not the
production path.

### Failure policy

If the curated content cannot be released (for example `quantity` has not been
imported yet, so `measurement`'s dependency pin cannot resolve), startup must
fail loudly rather than continue. The current failure mode is the whole reason
this bug exists: association silently defers everything and the pipeline
reports success. `ensureLLMUsageSink` already sets the precedent — log and
`os.Exit(1)`.

### This hole has already replicated

`server/cmd/doc-processing-policy-seed` is documented in its own header as
"Modeled on server/cmd/ontology-seed" and notes that its seeded pipelines "only
take effect in an already-running doc-processor". That is the same manual
out-of-band bootstrap pattern reproduced a second time. Whatever startup
mechanism is adopted here should be a shared one that both seeds use, so the
pattern stops spreading.

## Additional gaps found while verifying

### Deferred candidates are never reconsidered

After a candidate is deferred, `AssociateSemantics.Run` selects only rows in
`candidate` or `in_review` status. It does not reprocess existing `deferred`
rows merely because a governed term was later released.

The existing `/kb/semantic-decisions/drain-deferred` path filters on
`dependency_fingerprint = 'unresolved_referent'` exactly, so it does not drain
candidates deferred because a governed term was unavailable.

Therefore, installing the measurement module fixes future runs but does not by
itself provide a retry path for the three existing governed-term deferrals.

A retry path is straightforward to add: `deferCandidate` writes the full reason
into `dependency_fingerprint`, so the governed-term rows are selectable by the
`governed_term_not_released:` prefix.

### `ontology-seed` can report success while failing

`releaseAndActivate` prints `release ... skipped: %v` and returns when
`CreateRelease` fails; `main` continues and exits 0. A production run can
author the `mea:*` terms as `approved`, fail to release them, print a
success-looking line, and leave `associate_semantics` deferring exactly as
before. Until this is fixed, the command's exit code is not trustworthy and the
post-bootstrap verification queries below are a hard gate, not a formality.

### `ontology-seed` is only idempotent across clean runs

`authorModule` skips a term wholesale when the term row already exists, so a
run that dies between `CreateTerm` and its label inserts leaves a permanently
label-less term that no re-run repairs.

### The runtime gate and the proposed health check test different conditions

`termExists` consults only `kb.ontology_terms.status = 'included_in_release'`.
It never checks whether the term's release is the *active* one. A health check
written against "active `measurement` release" would go red on a rollback while
the runtime gate stayed green. Pick one condition and use it in both places.

### `exact_value` has no owner

`structuredValueAssertionKind` in `metric_normalizer.go` emits `exact_value`,
and the code comments document that no `mea:exact_value` term is seeded, so
such rows defer by design. This is deliberate and correctly described, but no
remediation item owns it, so those 6 candidates stay deferred indefinitely.
A decision is needed: seed `mea:exact_value`, or map `exact` onto
`observed_value`.

## Interim production bootstrap

Until the startup path exists, the measurement module can be installed against
`miner` with the standalone command and explicit environment mapping:

```bash
cd /Users/cding/Workspace/ChenWeb

mise exec -- sh -c '
  PG_USER="$PG_USER_NAME" \
  PGPASSWORD="$PG_PASSWORD" \
  PG_DB_NAME="$PG_DB_NAME" \
  go run ./server/cmd/ontology-seed --module all
'
```

Use `--module all` rather than `--module measurement`: `document-authority` is
missing from `miner` as well.

Because the command's exit code is unreliable, verify explicitly afterwards:

```sql
SELECT module_id FROM kb.ontology_modules ORDER BY 1;
SELECT module_id, version FROM kb.ontology_module_releases ORDER BY 1;
SELECT term_id, status FROM kb.ontology_terms
WHERE term_id IN ('mea:measured_by', 'mea:lower_bound_requirement');
```

Expected: a `measurement` module, an active `measurement@1.0.0` release, and
both `mea:*` terms at `status = 'included_in_release'`.

## Remediation needed

1. Move curated ontology bootstrap into service startup as an idempotent
   `EnsureCuratedModules(ctx, db)` called after `RunMigrations` in both
   `deepdoc` and `doc-processor`, failing loudly on error. Demote
   `ontology-seed` to a thin wrapper. Apply the same mechanism to
   `doc-processing-policy-seed`.
2. Bootstrap and verify the curated `measurement` **and** `document-authority`
   modules in `miner` (interim command above) so production is unblocked before
   item 1 ships.
3. Fix `releaseAndActivate` to fail non-zero when `CreateRelease` fails, and
   make `authorModule` re-check labels for terms that already exist.
4. Make the ontology CLI accept the same PostgreSQL environment naming as the
   services (`PG_USER_NAME`), and never default `PG_DB_NAME` to `chenweb_test`.
5. Track the missing deontic predicate vocabulary as its own item. It is the
   largest blocker (89 of 155 candidates for record 416) and is independent of
   all bootstrap work.
6. Decide the `exact_value` disposition: seed `mea:exact_value`, or map `exact`
   onto `observed_value`.
7. Add a governed-term dependency-fingerprint retry path for candidates
   deferred on the `governed_term_not_released:` prefix.
8. Reconcile the runtime term gate and any release health check so both test
   the same condition.
9. Decide whether accepted semantic assertions should carry a direct
   `metric_definition_term_id` reference. The current implementation keeps the
   metric identity on `kb.metrics` and only carries the metric name as an
   assertion qualifier; this is documented as a current limitation.
10. Add an integration test that runs the complete metric path against a
    freshly migrated database — with no manual seed step — and verifies the
    expected assertion/evidence rows. This test is what would have caught the
    bootstrap hole.
11. Make `authorModule` re-author a curated term whose latest version is
    neither `approved` nor `included_in_release`. Added by the follow-up
    review below (finding H); this is a startup-crash path.
12. Repair the `miner` activation pointers: every curated module's active
    release is an older, superseded one while the current curated content
    sits in an inactive release. Added by the follow-up review below.
13. Decide how a curated term is retracted. Deleting a term from
    `content.go` leaves it `included_in_release` forever, and the runtime
    gate accepts any released version. `mea:exact_value` is in exactly this
    state in `miner` today. Added by the follow-up review below.

## Implementation

Implemented in `ChenWeb` commit `fb27` (`Bootstrap curated ontology modules at
service startup`):

- Moved the curated `core`, `document-authority`, and `measurement` content
  plus its author/release/activation logic into the importable
  `server/api/ontology/seed` package.
- Added idempotent `seed.EnsureCuratedModules(ctx, db)` calls immediately after
  `RunMigrations` in both `server/cmd/deepdoc/main.go` and
  `server/cmd/doc-processor/main.go`. A bootstrap failure is now logged and
  terminates startup instead of allowing semantic association to defer
  silently.
- Retained `server/cmd/ontology-seed` as a thin wrapper over the same package.
  It now accepts the service-standard `PG_USER_NAME` (with `PG_USER` retained
  as a fallback), requires `PG_DB_NAME`, returns a non-zero exit on release
  failures, repairs missing labels left by a partial authoring run, and makes
  the curated release active when it already exists but is inactive.
- Added regression checks for the CLI database-environment contract and for
  both service startup call sites. Targeted tests and builds passed; the wider
  ontology test run still has unrelated failures in `ontology/keywords` and
  `cmd/qudt-import`.

This change has not been deployed and did not modify the production `miner`
database. The interim bootstrap and post-bootstrap verification remain
required until a binary containing this commit has been deployed and started.

Items 5–10 above, including the missing deontic predicate vocabulary and retry
of existing governed-term deferrals, remain separate follow-up work.

## Implementation review (2026-08-13)

Review of commit `fb2743a8` against this report. Each finding below was
verified against the source, `lib/pq` v1.11.2, and a read-only inspection of
`miner`. The package builds and vets clean, `go test ./server/cmd/ontology-seed/...`
passes, and the `errors.Is(err, sql.ErrNoRows)` guards are correct — the store
layer returns raw `sql.ErrNoRows`, not a wrapped error.

**Verdict: do not deploy as written.** Findings 1 and 2 convert a silent-defer
failure into a hard startup failure, which is a worse production posture than
the current behavior. The minimum before rollout is findings 1, 2, and 6.

### Correction to the Implementation section above

The claim that the change "did not modify the production `miner` database" and
that "the interim bootstrap and post-bootstrap verification remain required" is
no longer true. Verified in `miner` on 2026-08-13:

```text
kb.ontology_modules:          core, document-authority, measurement, quantity
kb.ontology_module_releases:  core@1.0.0, document-authority@1.0.0,
                              measurement@1.0.0, quantity@1.0.0
mea:measured_by               included_in_release
mea:lower_bound_requirement   included_in_release
```

Remediation item 2 is satisfied. Item 7 is confirmed still owed: record 416's
three governed-term candidates remain `deferred` on
`governed_term_not_released:mea:measured_by,mea:lower_bound_requirement` even
though both terms are now released, because nothing reprocesses them.

### Blocking defects

**1. A freshly migrated database can never bootstrap (circular dependency).**
`content.go:126` declares `measurement` with `DependsOn: {core, quantity}`, but
the `quantity` module row is registered only by `cmd/qudt-import` or by
deepdoc's own `/kb/ontology` QUDT handler (`qudt_ontology.go:193`). Neither
runs at startup. On a fresh database `CreateRelease` →
`validateAndBuildSnapshot` → `validateDeps` fails with *module "measurement"
depends on unknown module "quantity"*, so `EnsureCuratedModules` returns an
error and **both binaries `os.Exit(1)`** — including the very server needed to
run the QUDT import. This works against `miner` today only because `quantity`
was already imported.

This also makes remediation item 10 unachievable as specified: an integration
test on a freshly migrated database with no manual seed step cannot pass. That
test is exactly what would have caught this.

Fix: make `measurement`'s release conditional on `quantity` being releasable —
skip with a warning rather than fail fatally — or seed a minimal `quantity`
module stub so the dependency graph resolves before QUDT import.

**2. deepdoc hands the seed the 30-second `main()` context.**
`server/cmd/deepdoc/main.go:202` passes `ctx` from `main.go:46`
(`context.WithTimeout(context.Background(), 30*time.Second)`), while the
migrations directly above deliberately construct their own 3-minute context.
Any cold start where env load, DB init, and migrations together exceed 30s
hands the seed an already-expired context: `context deadline exceeded` →
`os.Exit(1)` → crash loop. `doc-processor` is unaffected; its `ctx` is
`context.WithCancel` with no deadline.

Fix: give the seed its own timeout context, as `RunMigrations` already does.

**3. Editing any curated prefLabel string is a fatal startup crash.**
`hasLabel` (`seed.go:105`) matches label text exactly, but `CreateLabel`
(`labels_store.go:111`) rejects a second prefLabel for the same (term, lang).
Renaming a label in `content.go` — the ordinary maintenance action this whole
design is built around, since curated content is meant to change by editing Go
source — makes every service `os.Exit(1)` against any database still holding
the old text. The status filters do agree (`hasLabel` and `prefLabelExists`
both exclude `rejected` and `superseded`), so label text is the sole
divergence. This is a side effect of the label-repair logic added for
remediation item 3.

Fix: supersede or version the existing prefLabel instead of attempting a
second insert, and never let a label mismatch be fatal.

**4. The hardcoded `1.0.0` silently recreates this bug's original symptom.**
`releaseAndActivate` (`seed.go:119`) looks up the release by `mc.Version`, and
all three curated modules are pinned at `1.0.0`. Adding a curated term without
bumping that constant means `GetRelease` succeeds, no new release is cut, and
the term stays `approved` forever — while the runtime gate
(`associate_semantics.go` `termExists`) requires `included_in_release`. That is
precisely the production symptom this report was filed for. Remediation item 6
(seed `mea:exact_value`) is exactly that edit. Nothing in the code or its
comments warns about it.

Fix: derive the release identity from the content checksum, or fail loudly when
the curated content no longer matches the existing release at that version.

**5. Unconditional `Activate` downgrades a newer release on every restart.**
`seed.go:136` — when the active release is not the hardcoded `1.0.0`, the seed
activates `1.0.0`. Both `cmd/ontology-compiler` and the QUDT API path create
releases at arbitrary versions, so a curated `measurement@1.1.0` would be
silently reverted at the next service start.

Fix: only activate when no release for the module is active.

**6. `envFirst("PG_USER_NAME", "PG_USER", "cding")` treats the default as a
variable name.** `server/cmd/ontology-seed/main.go:56`. The prior code was
`envOr("PG_USER", "cding")`, where `cding` was a value. Now `os.Getenv("cding")`
returns empty and the DSN is built with `user=`. In lib/pq v1.11.2 the OS-user
fallback is guarded by `if !cfg.isset("user")`, and `isset` tests key presence
(`connector.go:774`), so an empty `user=` *suppresses* the fallback rather than
triggering it. With neither variable set the connection fails with an empty
role rather than defaulting.

### Test and scope gaps

- **The new `server/api/ontology/seed` package has no tests** (`[no test files]`).
  All the behavior — `authorModule`, `releaseAndActivate`, `hasLabel`, module
  ordering — moved out of the CLI into an untested package. The two tests added
  are source-text greps over `main.go`, not behavioral tests.
- `server/cmd/ontology-seed/main_test.go:36` — the `bootstrap < migrations`
  assertion passes vacuously: if `config.RunMigrations` is ever renamed,
  `strings.Index` returns `-1` and the ordering check can no longer fail.
- **Remediation item 1's second half is not done.**
  `server/cmd/doc-processing-policy-seed` was untouched, so the manual
  out-of-band bootstrap pattern this report flagged as "already replicated"
  still exists in the tree.
- The uncommitted `mise.toml` `ontology-seed` task carries comments that this
  commit invalidated: it still states that `ontology-seed` "reads `PG_USER`"
  and "exits 0 even when a release fails". Its verifier also defaults
  `PG_HOST` to `127.0.0.1` while the Go seeder defaults to the `/tmp` socket,
  so with `PG_HOST` unset the task can verify a different cluster than it
  seeded.

### Recommendation

1. Block rollout on findings 1, 2, and 6.
2. Fix findings 3, 4, and 5 before the next edit to `content.go`; each is a
   latent trap armed by ordinary curated-content maintenance, and 4 silently
   reproduces the original bug.
3. Add behavioral tests for the `seed` package, and make the fresh-database
   integration test of item 10 the acceptance gate for finding 1.
4. Fold `doc-processing-policy-seed` into the same startup mechanism, or
   record explicitly that it is deferred and to whom.
5. Refresh the `mise.toml` task comments and reconcile its `PG_HOST` default
   with the seeder's.

### Implementation response (2026-08-13)

Review findings 1–6 were addressed in `ChenWeb` commit `447c` (`Harden curated
ontology bootstrap rollout safety`):

1. `core` and `document-authority` remain strict startup prerequisites, while
   `measurement` now defers nonfatally with a structured warning until
   `quantity` has an active release. This allows a fresh database to start and
   reach the QUDT import path.
2. Deepdoc now gives ontology bootstrap a dedicated three-minute context,
   matching the migration timeout rather than inheriting its 30-second main
   context.
3. Curated term and label changes now create approved versions for the next
   release; replacement preferred labels supersede the prior current label.
   This supports label-only edits after a previous release.
4. Curated release versions are derived deterministically from the compiled-in
   content, so a source change cannot silently reuse the prior release.
5. The seed path creates releases with `PreserveActive`, which leaves an
   operator-selected active release active and unsuperseded. Startup will not
   activate a newer curated release while any active release exists.
6. The CLI and `mise` task use the same trimmed PostgreSQL user resolution:
   `PG_USER_NAME`, then `PG_USER`, then literal `cding`. The task's verification
   now also uses the CLI's `/tmp` PostgreSQL host default.

Behavioral SQL-mock coverage was added for the fresh-database dependency
deferral, content-derived versions, active-release preservation, post-release
label and term-definition changes, and user fallback. Targeted tests and builds
passed. The wider ontology run still has the unrelated keyword resolver-mode
test failures noted above.

## Disposition

Bootstrap implementation hardening is accepted for deployment review. The
interim `miner` bootstrap (item 2) is done and verified. The policy-seed half
of item 1, the deontic predicate vocabulary, deferred governed-term retry, and
items 6–10 remain separate follow-up work; the deontic predicate vocabulary is
still the largest blocker for record 416.

## Hardening review (2026-08-13)

Review of commit `447cf8ec` against the six blocking findings above. Unlike the
previous round, the bootstrap paths were exercised against real, freshly
created PostgreSQL databases with `project_migrations` applied — not only
against SQL mocks. `go build ./server/...` and `go vet` are clean; the `seed`,
`ontology-seed`, and `modules` test packages pass; the `ontology/keywords`
resolver-mode failures remain and are unrelated, exactly as the implementation
response states.

**Verdict: findings 1–6 are correctly fixed. Two new defects of the same
family are live, so "blocking defects cleared" should not be read as "ready to
deploy."**

### Findings 1–6: verified fixed

1. **Fresh-database bootstrap.** On a freshly migrated database
   `EnsureCuratedModules` releases and activates `core` and
   `document-authority` and returns a `DeferredModuleWarning` for
   `measurement` instead of failing. Staging a `quantity` module with an
   active release and re-running then releases `measurement`, leaving
   `mea:measured_by` and `mea:lower_bound_requirement` at
   `included_in_release` — the exact condition `termExists` gates on.
   Re-running is idempotent: no additional module, term, label, or release
   rows.
2. **Deepdoc bootstrap context.** `server/cmd/deepdoc/main.go` now builds a
   dedicated three-minute `bootstrapCtx` rather than inheriting `main`'s
   30-second context. `doc-processor` remains on its deadline-free context.
3. **prefLabel edits.** Verified live against a database holding a prior
   release: the old preferred label is superseded and the replacement is
   authored and released. No fatal path remains.
4. **Content-derived versions.** A curated content edit cuts a new release,
   and a newly added curated term reaches `included_in_release` — so seeding
   `mea:exact_value` (item 6) will now actually take effect at runtime.
5. **Active-release preservation.** An operator-selected active release
   survives bootstrap; the new release is created inactive and unsuperseded.
6. **Database user resolution.** `postgresUserName()` resolves `PG_USER_NAME`,
   then `PG_USER`, then the literal `cding`. The `mise` task mirrors that
   resolution and now defaults `PG_HOST` to `/tmp`, matching the CLI.

The previously vacuous `bootstrap < migrations` assertion is also fixed: the
test now fails explicitly when either marker is absent.

### New defects

**A. A dangling curated module row turns any later content edit into a fatal
startup crash.** `validateAndBuildSnapshot` calls `validateDeps(allModules)`
(`modules/validate.go:191`), which validates the *entire* module graph rather
than the released module's transitive closure. `authorModule` registers a
module row before `releaseAndActivate` runs, so a failed
`ontology-seed --module all` against a database without `quantity` exits
non-zero but leaves the `measurement` row registered. Reproduced: from that
state, the next `core` content edit fails with *module "measurement" depends
on unknown module "quantity"*, and both binaries `os.Exit(1)`. This re-arms
finding 1's posture through a different door, and any module registered by any
path with an unregistered dependency has the same effect.

Fix: scope `validateDeps` to the closure of the module being released, or
refuse to register a module whose declared dependencies are not all registered.

**B. Reverting to previously released curated content is silently not
re-released.** `releaseAndActivate` (`seed/seed.go:270`) keys only on whether a
release already exists at the derived version. Reverting `content.go` to
content that a prior release already carries therefore finds that release,
skips creation, and strands `authorModule`'s corrected term version at
`approved` forever. Reproduced on a scratch database: after
original → edit → revert, `rev:x` holds v1 `ORIGINAL`
`included_in_release`, v2 `EDITED` `included_in_release`, and v3 `ORIGINAL`
`approved`. The state is stable rather than looping — further runs add
nothing — so the newest *released* content stays the reverted-away version
indefinitely, and `GetTermLatest` returns an unreleased row.

This is finding 4's failure mode mirrored: the content-derived version guards
against new content never being released, but not against reverted content
never being re-released.

Fix: after `releaseAndActivate`, verify every curated term's latest version is
`included_in_release` and cut a new release when it is not.

**C. Activation is frozen after the first bootstrap, and the freeze is
silent.** `releaseAndActivate` (`seed/seed.go:283`) returns as soon as any
active release exists, with no log line and no warning returned to the caller.
Every curated release after the first is therefore created inactive forever.
Real consumers read the activation pointer, not term status:
`ReleaseStore.LoadActiveModuleReleases`, the profile and profile-rule loaders,
and `VocabularyReleaseSQLStore.ActiveDocumentAuthorityReleaseID`, which pins
`classify_document`'s governed vocabulary. A `document-authority` content edit
will therefore never reach `classify_document`.

Fix: return a pending-activation warning alongside `DeferredModuleWarning` so
startup logs it, and consider advancing activation when the current pointer was
itself set by `ontology-seed` while preserving operator-selected activations.

**D. `moduleContent.Version` is dead code.** It is set to `"1.0.0"` for all
three modules (`seed/content.go:30`, `:62`, `:123`) and read nowhere;
`curatedReleaseVersion` hardcodes the `1.0.0` base. It still reads like the
release-version knob, so editing it looks meaningful and does nothing. Delete
it, or use it as the base of the derived version.

**E. `authorModule` never updates an existing module row.** Editing `Title`,
`Owner`, or `DependsOn` in `content.go` changes the derived release version —
forcing a new release — while `kb.ontology_modules` keeps the old values. That
stale row is what `validateAndBuildSnapshot` reads for dependency pinning, so a
curated `DependsOn` change is silently ignored.

**F. Item 8 now has three conditions in play, not two.** The runtime gate is
"any version at `included_in_release`"; the `mise.toml` verifier requires an
*active* release and inspects only the *newest* term row. Given finding C, that
verifier will report `ok measurement@1.0.0` indefinitely while curated content
moves on.

**G. `latestReleaseVersion` orders releases by `version` as text.** Among
`1.0.0+seed.<hex>` versions that ordering is arbitrary, so "the latest release"
of a curated module is effectively random. Only reachable when pinning a
dependency that has no active release.

### Test and scope gaps

- **The fresh-database integration test is still missing.** The previous review
  named it as finding 1's acceptance gate. The SQL-mock coverage added in
  `447c` is a real improvement, but nothing in the test suite exercises a
  freshly migrated database. Finding 1's fix was confirmed by hand for this
  review; a regression would not be caught automatically. Remediation item 10
  is now achievable and should become that gate.
- **`server/cmd/doc-processing-policy-seed` is untouched** and referenced by
  neither startup path, so the replicated manual-bootstrap pattern remains. The
  Disposition defers it but names no owner; the previous review asked for
  "deferred and to whom".
- **Remediation item 6 is under-specified.** Seeding `mea:exact_value` alone
  changes nothing: `governedMetricAssertionKinds`
  (`assertions/associate_semantics.go:170`) is a hardcoded Go allowlist that
  excludes `exact_value`, and it is consulted *before* `termExists`. The item
  can be marked done with no behavioral effect unless that map changes too.

### Effect on disposition

Deploying `447c` is not a no-op against an already-bootstrapped database. On
first start it authors a new content-derived release for each curated module
while leaving the pre-hardening `1.0.0` releases active, so the activation
pointers stay at `1.0.0` permanently (finding C) and the `1.0.0` releases end
up marked superseded while still being the active ones. That is worth an
explicit deployment note.

Findings A and B should be fixed before rollout: A can prevent both binaries
from starting, and B silently ships the wrong curated content — the failure
class this report exists to eliminate. C, D, E, F, and G are latent traps armed
by ordinary curated-content maintenance and should be fixed before the next
`content.go` edit.

## Implementation follow-up (2026-08-13)

Implemented in ChenWeb commit `228f` (`Harden curated ontology bootstrap
release handling`). This follow-up addresses findings A–G from the hardening
review:

- **A — dangling module dependencies:** release validation now checks only the
  target module's dependency closure. An unrelated registered module with an
  unresolved external dependency no longer prevents `core` or another
  independent module from releasing; the target module's own missing or cyclic
  dependencies still fail validation.
- **B — reverted content:** after finding an existing content-derived release,
  the seed verifies that every curated term and label is actually released. If
  a revert leaves the latest curated version approved, it stages the content
  and creates the next available `.r2`, `.r3`, ... release instead of silently
  reusing the old snapshot.
- **C — silent activation freeze:** preserving an operator-selected active
  release now returns a `pending_activation` bootstrap warning. Both
  `deepdoc` and `doc-processor`, as well as the CLI, log the warning.
- **D — release version base:** `moduleContent.Version` is now used as the
  base of the derived curated release version.
- **E — stale module metadata:** existing module `title`, `owner`, and
  `depends_on` values are reconciled from curated content before release
  validation.
- **F — verifier mismatch:** the `mise ontology-seed` verifier now checks for
  any `included_in_release` version of each gated measurement term, matching
  the runtime `termExists` gate rather than inspecting only the newest row.
- **G — lexical release ordering:** dependency fallback selection now uses
  release creation time (with ID as a tie-breaker), not lexical ordering of
  content-hash version strings.

Regression coverage was added for dependency-closure validation, reverted
content release selection, pending-activation warnings, curated metadata and
version handling, and release recency. The targeted ontology seed/module/CLI
tests pass; `go build ./server/...` and `go vet ./server/...` also pass.

The following items remain intentionally separate follow-up work, as already
noted in this report: the fresh-database integration acceptance test,
`doc-processing-policy-seed` startup integration, the missing deontic
predicate vocabulary, retrying existing governed-term deferrals, and the
`exact_value` vocabulary/allowlist decision.

## Follow-up review (2026-08-13)

Review of commit `228f4a35fb90` against findings A–G above. The bootstrap paths
were exercised against real, freshly created PostgreSQL databases with the
`kb.ontology_*` migrations applied, driving `SeedCuratedModules` and
`EnsureCuratedModules` directly. That was necessary rather than optional: the
regression coverage added in `228f` is entirely SQL-mock or source-text based
and does not reach the paths it claims to protect. `go build ./server/...` and
`go vet ./server/...` are clean, and the `seed`, `modules`, and `ontology-seed`
test packages pass, exactly as the implementation follow-up states.

**Verdict: A, B, D, E, and G are correctly fixed. C and F are half-fixed but
recorded as done. One new defect of the same family (H below) is a harder
failure than anything in A–G — it can hold both binaries in a permanent
`os.Exit(1)` loop — and it is a regression introduced by the B fix.**

### A, B, D, E, G: verified fixed

- **A — dependency-closure validation.** `validateAndBuildSnapshot` calls
  `validateDepsForModule` (`modules/validate.go:203`). Verified live: with a
  `dangling` module registered whose declared dependency `nowhere` does not
  exist, an unrelated module still releases *and* still accepts a subsequent
  content edit. The dangling module's own release still fails, correctly.
- **B — reverted content.** Verified live on a scratch database: an
  original → edit → revert cycle produced
  `1.0.0+seed.e19557dced1c.r2` with the reverted term at
  `included_in_release`. A fourth run added no module, term, label, or release
  rows, so the state is stable rather than churning.
- **D — release version base.** `curatedReleaseVersion` uses `mc.Version` as
  the base with a `"1.0.0"` fallback (`seed/seed.go:289`).
- **E — stale module metadata.** Verified live: `title`, `owner`, and
  `depends_on` are reconciled from curated content, and the reconciled
  `DependsOn` is honored by release-time dependency pinning.
- **G — release ordering.** `latestReleaseVersion` orders by
  `released_at DESC, id DESC`.

### H. New blocking defect: a non-approved curated term cuts a release on every start

`authorModule` decides whether to re-author a term by comparing kind, module,
and definition only (`seed/seed.go:143`) — it never inspects status. The label
path directly below it is status-aware (`hasLabel`, `seed/seed.go:196`), as are
`curatedContentReleased` (`seed/seed.go:378`) and
`stageContentForNewCuratedRelease` (`seed/seed.go:225`). A curated term left in
any other status is therefore never repaired, `curatedContentReleased` returns
false forever, and staging skips the broken term because its latest version is
not `included_in_release`.

Reproduced live by superseding one curated term of a two-term module and then
restarting the seed four times:

```text
restart 1: err=<nil> releases=2 termrows=3
restart 2: err=<nil> releases=3 termrows=4
restart 3: err=<nil> releases=4 termrows=5
restart 4: err=<nil> releases=5 termrows=6

sup:x v1 superseded            <- never repaired
sup:y v1..v5 included_in_release
release 1.0.0+seed.4e2feb306402
release 1.0.0+seed.4e2feb306402.r2 .r3 .r4 .r5
```

One new `.rN` release plus one new version row for every healthy sibling term,
on every service start, without bound. When the affected term is the module's
last curated term, the release cannot be built at all:

```text
== all-superseded restart err=release alltest@1.0.0+seed.765680673cf3.r2:
   module "alltest" has no approved terms to release
```

`EnsureCuratedModules` returns that error, so **both binaries `os.Exit(1)` on
every start** — the same posture findings 1 and A were filed to eliminate.

This needs no database surgery to trigger.
`POST /api/v1/kb/ontology/terms/:term_id/:version/status` (`routes.go:472`)
with `{"to": "superseded"}` is an allowed transition from
`included_in_release` (`terms/terms_store.go:92`), so an ordinary governance
action on a curated term arms it. Before `228f` this was impossible:
`releaseAndActivate` returned as soon as the derived-version release existed.
The B fix armed it.

Fix: make `authorModule` re-author a term whose latest version's status is
neither `approved` nor `included_in_release`, matching what the label path
already does. Tracked as remediation item 11.

### C and F are only half fixed

**C.** The `pending_activation` warning exists and is logged by `deepdoc`,
`doc-processor`, and the CLI. But activation itself still never advances:
`releaseAndActivate` (`seed/seed.go:353`) returns the warning and leaves the
pointer where it is. Verified live — a content edit released as release id 5
while the activation pointer stayed on id 4. Every consumer that reads the
pointer rather than term status keeps serving the first snapshot forever:
`ReleaseStore.LoadActiveModuleReleases`, the profile and profile-rule loaders,
and `VocabularyReleaseSQLStore.ActiveDocumentAuthorityReleaseID`
(`doc-processing/applicability_resolver.go:27`), which pins
`classify_document`'s governed vocabulary and does not filter superseded
releases. The hardening review's consumer-impact sentence — "a
`document-authority` content edit will therefore never reach
`classify_document`" — is still true. The implementation follow-up lists C as
addressed and the Disposition does not carry it forward as open work.

**F.** The `mise` verifier's term check now matches the runtime gate, which is
the half that was fixed. The module-level check still requires an *active*
release and prints that release's version, so with C open it reports
`ok core@1.0.0` indefinitely while curated content moves on. Confirmed in the
legacy-deploy simulation below. Item 8 therefore still has two conditions in
play, not one.

### Corrections to this report

**1. The activation-pointer inconsistency is not hypothetical — it is already
in `miner`.** The hardening review's "Effect on disposition" predicted that
deploying would leave the `1.0.0` releases "marked superseded while still being
the active ones". On a clean deploy of `228f` that does not happen:
`PreserveActive` protects the active release, and a simulated deploy over a
legacy `1.0.0` bootstrap left `1.0.0` active *and* unsuperseded. But the
prediction is nonetheless the live state of `miner` today, because the
10:34 run predates `PreserveActive`:

```text
module               active release      superseded_by   current content
core                 id=1  1.0.0         -> 10           id=15 (inactive)
document-authority   id=8  1.0.0         -> 11           id=11 (inactive)
measurement          id=9  1.0.0         -> 12           id=16 (inactive)
```

Every curated module's active release is a superseded one, and the release
carrying the current curated content is inactive. The runtime gate is still
green — `mea:measured_by` and `mea:lower_bound_requirement` both have
`included_in_release` versions — so `associate_semantics` is unaffected. But
`classify_document` and the profile loaders are pinned to the pre-hardening
snapshot. This needs an explicit repair step, not a deployment note. Tracked as
remediation item 12.

**2. Removing a term from `content.go` does not retract it, and that has
already happened.** `mea:exact_value` is `included_in_release` in `miner`
(released 11:10 in release id 13) but is no longer present in `content.go`.
There is no path back: the seed only ever adds. This is finding B's mirror
image. It also confirms empirically what the hardening review said about
remediation item 6 — the term is released and still inert, because
`governedMetricAssertionKinds` (`assertions/associate_semantics.go:170`)
excludes `exact_value` and is consulted before `termExists`. Tracked as
remediation item 13.

### Smaller items

- **Reverting only module metadata is silently not re-released.**
  `curatedContentReleased` inspects terms and labels only, so reverting
  `Title`, `Owner`, or `DependsOn` resolves the derived version back to an
  existing release, finds the content released, and cuts nothing. The newest
  release's dependency pins then stay stale. A narrow B-shaped hole left open.
- **`validateDeps` is now dead production code**, reachable only from its own
  three tests (`modules/validate.go:113`). Same shape as finding D, which this
  commit removed.
- **Staging cost is per release, not per changed term.** Every new
  content-derived release copies an approved version of *every* curated term.
  `miner` is already at 80 term rows for `core`'s 20 terms and 76 for
  `document-authority`'s 38.
- **`NextPatchVersion`'s comment is now wrong.** It still says "highest
  existing release version" (`modules/releases_store.go:305`) after the G fix
  made the underlying lookup recency-based. Only `quantity` uses it, so no
  behavior breaks.
- **`ontology-seed`'s package doc is now wrong.** It still states that
  "existing modules, terms, labels, and releases are skipped rather than
  overwritten" (`cmd/ontology-seed/main.go:11-14`). Re-running now updates
  module metadata, versions terms and labels, and can cut new releases.
- **New coverage does not reach the new code paths.** Nothing exercises
  `curatedContentReleased` or the revert flow end to end;
  `TestNextCuratedReleaseVersionReleasesRevertedContentAgain` tests only the
  version-string helper. The fresh-database integration test is still missing,
  which the implementation follow-up does acknowledge. Finding H would have
  been caught by a behavioral test over `authorModule` status handling.
- **Warning logging uses a dynamic message as the log key.**
  `logger.Warn(warning.String(), ...)` in both binaries, and
  `dependency_module_id` is emitted empty for `pending_activation`.

### Effect on disposition

Finding H should block rollout. It is a startup-crash path armed by an ordinary
governance action, and it is a regression this commit introduced rather than a
pre-existing trap. C should either be finished — advance activation when the
current pointer was itself set by `ontology-seed`, preserving operator-selected
activations — or moved explicitly to the follow-up list with an owner, since F
cannot be reconciled while C is open. The `miner` activation-pointer repair
(item 12) is independent of the code and can be done now.

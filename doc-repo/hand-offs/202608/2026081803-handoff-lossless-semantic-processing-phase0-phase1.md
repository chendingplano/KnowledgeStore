# Lossless Semantic Processing (ADR `2026081801`) — Phase 0 + Phase 1: Session Handoff

Date: 2026-08-18

## 1. State in one paragraph

ADR `2026081801` Phases 0 and 1 are **complete and committed**. Phase 2 is **in progress**:
tasks 5.1, 5.3, and 5.4 are complete, and the first document-scoped diagnostic reader slice
of 5.2 is committed. Phase 3 remains gated on completion and certification of all Phase 2
dual-read consumers; Phase 4 is not started.
Phase 0 (full-corpus baseline + capacity gate) passed on measured numbers, not estimates. Phase 1
landed the entire additive shared foundation — 8 migrations, a new family-generic `semantic` package,
the `represented` lifecycle, and the shadow-mode metric adapter — with **zero production behavior
change**: both writer gates default off, the metric adapter writes nothing, and
`associate_semantics` still fails a record on a proposed mapping exactly as it did before. ADR
`2026081701` foundations have since been implemented and archived in shadow mode, so the next
actionable work remains Phase 2 reader certification and Review Document rendering.

## 2. Document lineage (read in this order if picking this up cold)

1. **ADR `2026081801`** — `adrs/202608/2026081801-adr-lossless-semantic-processing-and-knowledge-preservation.md`.
   The decision. DR1–DR13. Section 5 is the phase plan this work follows verbatim.
2. **Impl doc `2026081802`** — `impl/202608/2026081802-impl-lossless-semantic-phase0-and-phase1.md`.
   The Phase 0 numbers, the gate decision, the ADR `2026081701` reconciliation table, and the
   rollback defect found by testing. **Section 2 is the most important part of this whole body of
   work** — it is the only place the two ADRs' seams are written down.
3. **OpenSpec change** — `ChenWeb/openspec/changes/lossless-semantic-processing/`.
   `proposal.md` (why), `design.md` (D1–D10 technical decisions with rejected alternatives),
   `specs/*/spec.md` (8 capabilities as testable WHEN/THEN scenarios), `tasks.md` (phased 0–4,
   44/72 checked).
4. **ADR `2026081701`** — `adrs/202608/2026081701-adr-canonical-metric-classes-instances-and-semantic-relations.md`.
   Read DR8 and DR9 before touching claim identity. Its canonical foundations are now implemented
   in shadow mode; see §6 for the activation boundary.
5. **ADR `2026081401`** — governed metric vocabulary. Its DR3/DR6 mapping-miss *failure* behavior is
   superseded by DR12 of `2026081801`, but only that; its governed table, discovery, occurrence
   counting, and Phase-C failure reporting all remain authoritative.

## 3. What was built

All in jj change `stlykvnsxpxy` / git `ba6d00e4`, "2026081801-adr Phase 1 implementation + other bug
fixes". **Caveat:** that commit also carries unrelated in-flight work that was already in the tree
(evidence-provenance enrichment in `associate_semantics.go`, `llmreporthandler`, several `web/`
files, `qudt-import`). Do not read the whole commit as this session's output; the inventory below is.

### Migrations (`ChenWeb/project_migrations/`)

| Migration | Adds |
|---|---|
| `20260818000001` | `kb.semantic_processing_outcomes` + `uq_semantic_processing_outcomes_active` |
| `20260818000002` | `kb.semantic_processing_findings` + `uq_semantic_processing_findings_active` + **two deferred constraint triggers** (both directions of the active-parent/active-child invariant) |
| `20260818000003` | `kb.unresolved_semantic_occurrences` + `uq_unresolved_semantic_occurrences_active` |
| `20260818000004` | `kb.semantic_retry_queue`, unique on `(outcome_id, finding_id, target_dependency_fingerprint)` **with `NULLS NOT DISTINCT`** |
| `20260818000005` | `kb.semantic_adapter_compliance` |
| `20260818000006` | `represented` status + `unsupported_prior_status` |
| `20260818000007` | The four governed state columns, raw payload/fingerprint, error details |
| `20260818000008` | Value-state-aware payload constraint replacing `chk_semantic_assertions_object_ref_or_literal` |

### Code

- **`ChenWeb/server/api/ontology/semantic/`** — new package, family-generic by design (nothing in it
  knows what a metric is except `metric_adapter.go`):
  - `terms.go` — 52 governed identifiers + `ValidateGovernedIdentifier`, which rejects hyphenated
    display labels with a distinct error message.
  - `execution.go` — binary `ExecutionStatus`, `OutcomeCategory`, `LegacyProcStatus`,
    `FindingSummary`, and DR3's required-vs-optional service classification.
  - `fingerprint.go` — `v1:`-prefixed canonical fingerprints; `OutcomeKey`, `OccurrenceKey`,
    `FindingKey`; length-prefixed joins so artifact IDs cannot collide across field boundaries.
  - `outcomes.go` — `OutcomeStore.Record`, the single write path: locks the scope, replays
    idempotently, supersedes transactionally, derives `finding_count`/`highest_severity` from children.
  - `occurrences.go` — DR13 fallback store with leases and transactional materialization.
  - `retry.go` — `RetryQueue` with skip-locked claims, staleness on both axes, targeted scheduling.
  - `adapter.go` / `conformance.go` — `FamilyAdapter` contract, registry, conformance suite,
    `AuthorizeWriterActivation`.
  - `completeness.go` — `CompletenessChecker`, the cutover gate.
  - `report.go` — DR11 per-run reporting.
  - `gates.go` — `LOSSLESS_SEMANTIC_WRITES_METRIC`, `LOSSLESS_SEMANTIC_FALLBACK_WRITES`, per-family deny.
  - `metric_adapter.go` — declaration + `RunShadow` (read-only).
- **`ChenWeb/server/cmd/semantic-baseline/`** — the Phase 0 report command.
- **`ChenWeb/server/api/ontology/assertions/state_machine.go`** — `represented` + evidence
  loss/restoration edges, `EvidenceLossTransitionAllowed`, `ValidUnsupportedPriorStatus`.
- **`ChenWeb/server/api/ontology/seed/content.go`** — the `semantic-processing` curated module.
  Also added to the strict bootstrap batch in `seed.go` and to `cmd/ontology-seed`'s target list.

## 4. Phase 0 findings that were not in the ADR

Three things the corpus said that the ADR did not:

1. **99.24% loss, not "roughly 100×".** 7,020 of 7,074 metric occurrences have no current supporting
   assertion link. The ADR's framing was right; the exact figure is now measured and re-runnable.
2. **17 metric occurrences already carry duplicate current supporting links.** These will make
   `CREATE UNIQUE INDEX uq_assertion_evidence_current_metric_support` fail. Phase 3 task 6.2 exists
   for exactly this and must run before 6.3. Do not discover this at migration time.
3. **`kb.metrics.value_range_type_error` is set on 0 of 7,074 rows.** ADR `2026081401`'s
   artifact-level error flag has never once fired in this corpus. Any plan that assumes it is the
   mechanism surfacing mapping problems is wrong; the outcome/finding store is.

Also worth carrying forward: only **206** metric decision candidates exist for **7,074** metrics, so
the deferral-reason counts understate the loss by ~34×. This is why DR1's invariant is stated over
*artifacts*, never over candidates.

Measured capacity (load test, not projection): 21,222 envelopes written in 6.3 s (3,387/sec),
idempotent replay at 2,746/sec appending zero rows, retry sweep 10 ms over 1,011 affected findings,
completeness projection 69 ms over 7,074 artifacts, 16.3 MiB total with **55% of that in indexes**.
That index ratio is why `bytesPerOutcome` in the baseline command is 806 and not the 512 originally
guessed.

## 5. What was deliberately NOT built

- **Phase 2** (dual-read consumers) — in progress; the consumer audit, state-bearing reader API,
  comparison behavior, and first document-scoped diagnostic endpoint are complete. Review Document
  rendering and reader certification remain.
- **Phase 3** (metric lossless writer) — canonical foundations are available, but activation remains
  gated on Phase 2 certification; see §6.
- **Phase 4** (generic fallback activation, other families) — not started.
- **No writer was enabled.** `associate_semantics.Run` still returns its aggregate mapping-miss error
  at [associate_semantics.go:108](../../../../ChenWeb/server/api/ontology/assertions/associate_semantics.go) and still drives assertions to `accepted`. Removing those
  is task 6.6, in Phase 3, because doing it earlier would expose `represented` rows to consumers that
  have not been certified to read them.
- **No per-family adapter authoring guide.** One adapter exists and it is a declaration, not a
  writer. A guide written from a single non-writing example would be documenting guesses.

## 6. Canonical-foundation status and Phase 3 activation boundary

The former Phase 3 blocker is resolved. The `canonical-metric-class-foundations` OpenSpec change
was fully implemented, certified with writers off, and archived in ChenWeb commit `cae1a23f`.
It provides stable/provisional class assignment, claim identities and canonical-key registry,
claim-backed assertion compatibility projection, bounded acyclic assertion/term redirects,
class-resolution decisions, duplicate supporting-link cleanup, and the current-metric support
uniqueness rule. Shadow reports and the activation handoff are recorded in KnowledgeStore.

This does **not** enable the lossless metric writer. Phase 3 task 6.9 remains gated on Phase 2
reader certification plus a passing completeness projection. Until then, legacy writer behavior
remains intentionally unchanged and both lossless writer gates remain off.

Two conflicts between the ADRs were found and resolved during Phase 0; both are recorded in impl doc
`2026081802` §2.2 and should not be re-litigated silently:

- **Disposition never selects the canonical identity branch.** A parsed-but-unmapped metric is
  disposition `raw_preserved` while its claim identity still uses `normalized_value`. `2026081801`
  DR2 is normative here; `2026081701` is silent.
- **`unsupported_prior_status` is a column on `kb.semantic_assertions`**, not a side table —
  restoration must be a single-row transactional read, and a join would put the constraint beyond
  the database's reach.

## 7. Verification — copy-pasteable

```bash
cd ~/Workspace/ChenWeb

# Phase 0 baseline (read-only, safe against production)
PG_DB_NAME=miner PG_HOST=127.0.0.1 go run ./server/cmd/semantic-baseline/ --format markdown

# Unit + integration tests (integration creates and drops its own scratch databases)
TEST_DATABASE_URL='host=127.0.0.1 user=cding dbname=postgres sslmode=disable' \
    go test ./server/api/ontology/semantic/ ./server/api/ontology/assertions/ \
            ./server/api/ontology/seed/ ./server/cmd/semantic-baseline/ -count=1

# Corpus-scale load test (opt-in; ~10s)
SEMANTIC_LOAD_TEST=1 TEST_DATABASE_URL='host=127.0.0.1 user=cding dbname=postgres sslmode=disable' \
    go test ./server/api/ontology/semantic/ -run LoadTest -v -timeout 30m
```

**Two pre-existing failures are unrelated to this work** and were present at HEAD before it:
`ontology/keywords` `TestResolverModeFromUnsetIsOff`, and `cmd/qudt-import` TTL parsing. Do not
chase them as regressions from this change.

## 8. Traps for the next session

- **`TEST_DATABASE_URL` must name a template database (`dbname=postgres`), never `miner`.** The
  integration tests parse it as a connection template and `CREATE DATABASE` their own scratch DB per
  test. Pointing it at `miner` is separately dangerous — some tests elsewhere in this repo
  unconditionally wipe `module_id='quantity'` rows.
- **The metric adapter self-registers in `init()`.** Any test that calls `RegisterAdapter` must call
  `resetAdaptersForTest()` first (registering twice for one artifact type panics on purpose).
- **`goose` Down steps containing `DO $$ ... $$` need `-- +goose StatementBegin/End` markers.**
  Migrations `20260818000006` and `20260818000008` both have them; omitting them produces an
  "unterminated dollar-quoted string" error only on the *down* path, which is easy to miss.
- **Both those Down steps are deliberately defensive.** They refuse to narrow a constraint when rows
  exist that would violate it, emitting a `NOTICE` instead. This is ADR §6's "a rollback does not
  delete committed raw-preserved assertions" made real — writing the rollback test is what exposed
  that the naive version was impossible. Do not "simplify" them.
- **`NULLS NOT DISTINCT` requires PostgreSQL 15+.** Dev is on 18.2. It is what makes two whole-stage
  retry enqueues (null `finding_id`) collide instead of duplicating.
- **`AggregateFingerprint` takes a stage fingerprint *string*, and always aggregates** — even with
  zero children. Mixing bare stage fingerprints and aggregates in one column would make the replay
  comparison depend on whether the previous attempt happened to have findings.
- **Partial unique indexes enforce "at most one", never existence.** Every time the ADR says
  "exactly one", the existence half comes from the atomic transaction plus
  `CompletenessChecker`. If you add an invariant, add it in both places.

## 9. Phase 2 progress and where to resume

Completed Phase 2 tasks:

- **5.1** lifecycle-consumer audit is at
  `ChenWeb/openspec/changes/lossless-semantic-processing/consumer-lifecycle-policy.md`.
  Governance/profile readers stay accepted-only; diagnostic and discovery readers must be dual-read.
- **5.3** assertion reader responses expose the independent semantic-state, raw-preservation, error,
  and contract-revision fields before any default filtering changed.
- **5.4** directional comparison persists `no_verdict`/`incomparable_with` with a reason rather
  than dropping unsupported inputs.
- **5.2 first slice** — ChenWeb commit `f6678780` adds
  `GET /api/v1/kb/semantic-assertions?input_record_id=<id>`. It returns every assertion with an
  active evidence link to that document, including `represented`, `unsupported`, ambiguous, and
  missing/raw-preserved states; it does not widen accepted-only governance queries. Focused store
  and HTTP-handler tests pass.

**Resume with Review Document rendering (task 5.5):** add a read-only diagnostic section/tab to
the existing Review Document results view. It should call the document-scoped assertion endpoint
and show the claim, raw and normalized values, independent states, processing errors, class
confidence, and active evidence. Do not route these assertions through the accepted-only
profile-rule loader or present “completed with findings” as a processing failure.

Then complete 5.2's remaining consumers (semantic projection, reports, retry tooling), 5.6 search /
observed-profile / completeness behavior, 5.7 reader compatibility certification, 5.8 dashboard
semantics, and 5.9 legacy-writer gate. Only then proceed to Phase 3 task 6.9 activation.

Open questions still outstanding (ADR §10): raw-fragment retention/compaction; default Review
Document filters by severity; the first non-metric family to migrate. Newly added: whether
`kb.semantic_retry_queue` should share the failed-processor worker pool — the 10 ms sweep suggests a
dedicated pool is unnecessary at current scale, deferred to Phase 3.

# 2026081802 — Lossless Semantic Processing: Phase 0 Gate and Phase 1 Foundation

**Date:** 2026-08-18 \
**Status:** Phase 0 complete; Phase 1 complete (writers off) \
**Implements:** ADR `2026081801` (lossless semantic processing and knowledge preservation) \
**OpenSpec change:** `openspec/changes/lossless-semantic-processing/` \
**Coordinates with:** ADR `2026081701` (unimplemented — see §2)

## 1. Phase 0 corpus baseline

Produced by `server/cmd/semantic-baseline`, a checked-in read-only command so the
same report is re-runnable as the pre-cutover comparison basis.

```bash
PG_DB_NAME=miner PG_HOST=127.0.0.1 go run ./server/cmd/semantic-baseline/ --format markdown
```

### 1.1 The measured loss

| Measure | Value |
|---|---:|
| Input records | 209 |
| Records with metrics | 58 |
| Metric occurrences | 7,074 |
| Semantic assertions | 253 (236 `accepted`, 17 `superseded`) |
| Active evidence links (all families) | 71 |
| Active metric supporting links | 71 |
| Metric occurrences with duplicate current support | 17 |
| **Metric occurrences with no current supporting link** | **7,020** |

**99.24% of metric occurrences are semantically unreachable today.** The ADR's §8.2
framing ("71 current assertion links to 7,074 occurrences — roughly 100×") is confirmed
by direct measurement.

Two findings the ADR did not anticipate:

1. **17 metric occurrences already carry duplicate current supporting links.** These block
   `uq_assertion_evidence_current_metric_support` and must be resolved by the auditable
   backfill (Phase 3 task 6.2) before that index can be created.
2. **`value_range_type_error` is set on 0 of 7,074 rows.** ADR `2026081401`'s artifact-level
   error flag has never fired in this corpus, so it cannot be the mechanism that surfaces
   mapping problems; the outcome/finding store is.

### 1.2 Range-type mapping states

| Mapping state | Metric occurrences | Distinct raw values |
|---|---:|---:|
| `approved` | 4,276 | 51 |
| `absent` | 1,366 | 0 |
| `unmapped` | 803 | 211 |
| `ambiguous` | 629 | 7 |

`unmapped` (no row in `kb.metric_value_range_type_map` yet) becomes `proposed` on first
sighting by `ValueRangeTypeMapper.Lookup`, which auto-inserts. Under ADR `2026081401` DR3
each of those 803 occurrences is a candidate for failing `associate_semantics`; under this
ADR each becomes a `mapping_unresolved` finding on a raw-preserved assertion.

The 211 distinct unmapped raw values against 51 approved ones is the concrete size of the
governed-vocabulary gap.

### 1.3 Current deferral reasons

| Reason | Count |
|---|---:|
| `no_governed_deontic_predicate` | 89 |
| `no_governed_assertion_kind_term:` | 40 |
| `unresolved_referent` | 2 |
| `no_governed_assertion_kind_term:unparsed` | 1 |

Only 206 metric decision candidates exist for 7,074 metrics: most occurrences never reach
`normalize_assertions` as candidates at all, so deferral reasons understate the loss by
roughly 34×. This is why DR1's invariant is stated over *artifacts*, not over candidates.

### 1.4 Capacity model

Required metric stages (declared by `MetricAdapter.RequiredStages`):
`semantic:stage_normalize`, `semantic:stage_class_resolution`, `semantic:stage_associate`.

| Projected row set | Rows |
|---|---:|
| Evidence links | 7,074 |
| Class-resolution decisions | 7,074 |
| Outcome envelopes (7,074 × 3) | 21,222 |
| Findings (low estimate) | 1,432 |
| Findings (high estimate) | 21,222 |
| Assertions before canonical convergence | 7,074 |
| **Estimated bytes (worst case)** | **36.6 MiB** |

The low finding estimate is the measured `unmapped` + `ambiguous` population (803 + 629);
the high estimate assumes one finding per occurrence per required stage.

### 1.5 Load test (measured, not projected)

`TestIntegrationLoadTestCorpusScale` writes the full corpus shape against a fresh
migrated database:

```bash
SEMANTIC_LOAD_TEST=1 TEST_DATABASE_URL='host=127.0.0.1 user=cding dbname=postgres sslmode=disable' \
    go test ./server/api/ontology/semantic/ -run LoadTest -v -timeout 30m
```

| Measure | Result |
|---|---|
| Write 21,222 envelopes + 1,011 findings | 6.27 s (3,387 envelopes/sec) |
| Full-corpus idempotent replay | 2.58 s (2,746 replays/sec), 0 rows appended |
| Targeted retry sweep (1,011 affected findings) | 10 ms |
| Completeness projection over 7,074 artifacts | 69 ms |
| `kb.semantic_processing_outcomes` size | 16.3 MiB total, 9.0 MiB indexes |

Index overhead is 55% of total relation size — four indexes (base revision uniqueness,
active-row partial uniqueness, artifact lookup, stage lookup) on a narrow table. The
capacity model's `bytesPerOutcome` was corrected from an estimated 512 to the measured 806
bytes on this basis.

The deferred constraint triggers added no measurable cost at this scale; the write rate is
dominated by the per-attempt transaction, not by trigger evaluation.

### 1.6 Gate decision

| Gate | Threshold | Result |
|---|---|---|
| Full-corpus coverage | All 58 metric-bearing records reported | **Pass** (58/58) |
| Storage | Same order of magnitude as existing kb tables | **Pass** (36.6 MiB projected) |
| Write throughput | Corpus writable within a normal processing window | **Pass** (6.3 s) |
| Replay idempotency | Re-run appends no rows | **Pass** (0 appended) |
| Retry targeting | Unchanged dependency enqueues nothing | **Pass** (verified in tests) |
| Completeness projection latency | Usable as a cutover gate | **Pass** (69 ms) |
| Rollback | Phase 1 migrations reversible without data loss | **Pass** (see §3.3) |

**Phase 1 is authorized.** Phase 3 is not: see §2.

## 2. Reconciliation with ADR `2026081701` (Phase 0 task 1)

ADR `2026081701` has **no migrations and no Go code**: there is no `claim_id`, no
`kb.semantic_claim_identities`, no canonical-key registry, no class-resolution decision
table, and no assertion or term redirects. Everything in ADR `2026081801` that names those
is blocked.

### 2.1 Agreed seams

| Concern | Owner | How Phase 1 leaves the seam |
|---|---|---|
| Cross-family minimum assertion field/state contract | `2026081801` DR6 (normative) | Columns added by migration `20260818000007`; `2026081701` DR8 projects onto the same names |
| `represented` lifecycle + `unsupported_prior_status` | `2026081801` DR6 (normative) | Added by `20260818000006`; both ADRs describe it identically |
| Value states (`present`/`missing`/`unparsed`/`datatype_mismatch`/`unknown`/`not_applicable`) | Both; identical lists | Seeded as governed terms in the `semantic-processing` module |
| Metric canonical claim payload and identity | `2026081701` DR9 (normative) | Not implemented here. `Dependencies`/`AggregateFingerprint` cover *dependency* identity only, never claim identity |
| Class identity, contracts, provisional classes | `2026081701` DR2/DR3/DR7 | `class_identity_state_term_id` column and `semantic:stage_class_resolution` stage exist; nothing populates them |
| Assertion/term redirects | `2026081701` DR9 | Not implemented; DR10's "identity-bearing change resolves a different `claim_id`" is unenforceable until it is |
| `normalized_against_contract_revision_id` | `2026081701` DR2 | Column declared here (DR6 lists it in the minimum contract), semantics owned there |

### 2.2 Conflicts found and how they were resolved

1. **Disposition versus identity branch.** `2026081801` DR2 says outcome disposition must not
   select the canonical identity branch — a parsed-but-unmapped metric is `raw_preserved` yet
   converges by `normalized_value`. `2026081701` DR9 is silent on this. **Resolution:** DR2 is
   normative (this ADR governs cross-family lossless states); recorded as a spec scenario in
   `specs/lossless-semantic-processing/spec.md` and asserted in the metric adapter's shadow
   logic, which sets `raw_preserved` on mapping state while leaving value state `present`.
2. **Where `unsupported_prior_status` lives.** ADR §10 open question 1. **Resolution:** a column
   on `kb.semantic_assertions`, constrained to be non-null only when `status = 'unsupported'`.
   A side table was rejected: restoration must be a single-row transactional read, and a join
   would make the constraint unenforceable by the database.
3. **Claim-registry ordering.** `2026081801` Phase 1 item 6 asks Phase 1 to coordinate with
   `2026081701` Phase 1. **Resolution:** deferred. Phases 0–2 of this change are deliberately
   scoped to be independent of the claim registry; nothing in Phase 1 writes
   `logical_identity_key` or depends on its format.

### 2.3 Blocking list for Phase 3

Phase 3 cannot start until `2026081701` delivers: stable class identity and provisional
class creation; `kb.semantic_claim_identities` with
`(identity_scope, canonical_key_version, canonical_digest)` uniqueness; `claim_id`-backed
`logical_identity_key`; assertion/term redirect resolution; and the class-resolution decision
table. Tasks 6.1–6.12 in `tasks.md` are marked blocked accordingly.

## 3. Phase 1 delivery

### 3.1 Schema (`project_migrations/`)

| Migration | Adds |
|---|---|
| `20260818000001` | `kb.semantic_processing_outcomes` + `uq_semantic_processing_outcomes_active` |
| `20260818000002` | `kb.semantic_processing_findings` + `uq_semantic_processing_findings_active` + both deferred constraint triggers |
| `20260818000003` | `kb.unresolved_semantic_occurrences` + `uq_unresolved_semantic_occurrences_active` |
| `20260818000004` | `kb.semantic_retry_queue` (unique on `(outcome_id, finding_id, target_dependency_fingerprint)` with `NULLS NOT DISTINCT`) |
| `20260818000005` | `kb.semantic_adapter_compliance` |
| `20260818000006` | `represented` status + `unsupported_prior_status` |
| `20260818000007` | The four governed state columns, raw payload/fingerprint, error details |
| `20260818000008` | Value-state-aware payload constraint replacing `chk_semantic_assertions_object_ref_or_literal` |

All additive. No existing raw artifact row is rewritten or deleted.

### 3.2 Code

- `server/api/ontology/semantic/` — new shared, family-generic package: governed vocabulary
  with alias rejection, binary execution status with the `LegacyProcStatus` projection,
  canonical versioned dependency fingerprints, outcome/finding store with transactional
  supersession, unresolved-occurrence store with leases and transactional materialization,
  dependency-driven retry queue, family adapter contract + conformance suite + activation
  refusal, completeness projection, DR11 run reporting, writer gates (default off), and the
  shadow-mode metric adapter.
- `server/api/ontology/assertions/state_machine.go` — `represented` and the evidence
  loss/restoration edges.
- `server/api/ontology/seed/content.go` — the `semantic-processing` governed module (52 terms).
- `server/cmd/semantic-baseline/` — the Phase 0 report command.

**No production behavior changed.** The metric adapter registers itself but writes nothing;
both writer gates default off; `associate_semantics` still returns its aggregate mapping-miss
error (removing it is task 6.6, Phase 3).

### 3.3 Rollback

Verified by `TestIntegrationPhase1MigrationsRollBackCleanly`: all eight migrations roll back,
every new table is dropped, committed assertion rows survive, and re-applying succeeds.

Writing that test found a real defect. The first version of `20260818000006`'s Down step
narrowed the `status` CHECK unconditionally, which fails once any `represented` row exists —
a rollback would have been impossible without deleting committed claims, contradicting ADR
§6 ("does not delete committed raw-preserved assertions"). The Down step now leaves the
widened vocabulary in place and emits a NOTICE when such rows exist. The legacy writer never
emits `represented`, so the widened constraint is harmless to it.

### 3.4 Tests

- Unit: fingerprint stability/versioning/collision, governed-alias rejection, binary
  execution status, finding summaries, service-failure classification, gates, lifecycle shape.
- Integration (fresh scratch database per test, full migrations): idempotent replay,
  transactional supersession with child deactivation, multiple independent findings under one
  envelope, per-artifact isolation, artifact-required constraint, unidentified invocation
  creating no occurrence, every value-state payload rule, `unsupported_prior_status` rules,
  retry idempotency/leases/staleness/targeting, occurrence lifecycle and materialization
  rollback, completeness detection, activation refusal, shadow mode writing nothing,
  8-worker concurrency, and migration rollback.

## 4. Open questions still outstanding

Carried from ADR §10, unchanged: raw-fragment retention and compaction (§10.2); default
Review Document filters by severity (§10.3); the first non-metric family to migrate (§10.4).
Resolved: the physical location of `unsupported_prior_status` (§10.1, see §2.2 above).

Added by this implementation: whether `kb.semantic_retry_queue` should share the
failed-processor worker pool. The 10 ms sweep over 1,011 jobs suggests a dedicated pool is
unnecessary at current scale; deferred to Phase 3.

## 5. Documentation status

- **Updated:** this document; `openspec/changes/lossless-semantic-processing/` (proposal,
  design, 8 capability specs, phased tasks).
- **Now stale:** `metric-assertion-semantic-processing-v1.2-en.md` still describes
  mapping misses as processor failures. It stays accurate until Phase 3 flips the writer;
  task 8.3 updates it at cutover.
- **Intentionally undocumented:** per-family adapter authoring guidance. One adapter exists
  and it is a declaration, not a writer; writing a guide from a single non-writing example
  would document guesses.

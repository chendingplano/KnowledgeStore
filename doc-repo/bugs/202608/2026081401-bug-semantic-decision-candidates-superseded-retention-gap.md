# `superseded` decision-candidate (and assertion) revisions accumulate forever — no retention policy exists, and the dev DB shows one record already driving 60% of the table

Date: 2026-08-14

Status: root-caused against live `miner` data; no fix implemented yet.

Scope: `kb.semantic_decision_candidates.status = 'superseded'` (primary), and the structurally
identical `kb.semantic_assertions.status = 'superseded'` (same latent risk, not yet manifested in
current data). Not a correctness bug in `associate_semantics` or `normalize_assertions` — the
supersede mechanism itself works as designed (see
[[project_object_reconciliation_ambiguous]] history and
`2026081302-bug-metric-semantic-association-does-not-converge-automatically.md` for how revisions
get created). This is a data-lifecycle gap: nothing ever prunes, archives, or bounds the rows once
they're superseded.

Code read: `server/api/ontology/assertions/{decision_candidates_store.go,assertions_store.go,
state_machine.go,associate_semantics.go,telemetry.go}`, migrations
`20260801000004_create_kb_semantic_decision_candidates.sql`,
`20260801000001_create_kb_semantic_assertions.sql`, `20260801000002_create_kb_assertion_evidence.sql`.
Searched the whole `ChenWeb` tree for `retention|archive|purge|ttl` and for any `DELETE FROM
kb.semantic_decision_candidates` / `kb.semantic_assertions` — none exist. Searched
`KnowledgeStore/doc-repo/adrs/` for any retention decision covering this table.

Related: [[project_ontology_candidates_harvest_mechanics]],
`2026081101-bug-ontology-candidates-fingerprint-dedup.md` (the sibling P2 table, same
"additive-only, no delete" pattern, already flagged there), ADR
`202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` §OD6 and §DR24, ADR
`202606/2026062102-adr-llm-accounts.md` (existing precedent: `llm_usage_event` retention job —
see Recommended remediation), `2026081302-bug-metric-semantic-association-does-not-converge-automatically.md`
(the record-416 debugging history that produced the live evidence below).

---

## Summary

Every time `normalize_assertions` re-proposes a candidate whose `payload_fingerprint` differs from
the immediately prior revision, `DecisionCandidateStore.Propose` inserts a new row and flips the
prior revision to `status = 'superseded'` (`decision_candidates_store.go:275-292`). The identical
pattern exists for `kb.semantic_assertions` via `CreateRevision`
(`assertions_store.go:296-360`). Both are correct, intentional behavior — the design explicitly
wants a full revision history rather than mutating rows in place (`decision_candidates_store.go:9-13`
comment; `assertionTransitions` in `state_machine.go:27-49`).

But nothing ever removes, archives, or bounds these `superseded` rows. There is no delete path, no
archive table, no scheduled job, and no age/count cap anywhere in the codebase. The only place a
retention *decision* is even discussed is ADR `2026072901` §OD6 — and it explicitly scopes itself
to `unsupported` assertions and `rejected` candidates only ("Deferred (spec §17.10); indefinite
audited retention until decided"), plus §DR24's non-goals list, which again names only
`unsupported`. **`superseded` is never mentioned in either place.** It fell outside the one
retention conversation the design already had.

This is not theoretical. Querying the live dev database (`miner`) today:

```sql
SELECT status, count(*) FROM kb.semantic_decision_candidates GROUP BY 1 ORDER BY 2 DESC;
--  superseded | 233
--  deferred   |  91
--  candidate  |  64
```

**233 of 388 rows (60%) are already `superseded`**, in a system where only 147 assertions have
ever been accepted total (`kb.semantic_assertions` has exactly one status value present today:
`accepted | 147` — no assertion has been superseded yet, so the assertion-table version of this
bug is latent, not yet manifested).

## Where the 233 rows came from — a single record, reprocessed repeatedly

```sql
SELECT count(DISTINCT input_record_id) AS distinct_records,
       count(*) FILTER (WHERE status='superseded') AS superseded_rows
FROM kb.semantic_decision_candidates;
--  1 | 233
```

All 233 superseded rows belong to **one** `input_record_id` (416 — the same record from
`2026081302-bug-metric-semantic-association-does-not-converge-automatically.md`, which was
reprocessed/re-reviewed across three implementation rounds on 2026-08-13/14). Revision-count
distribution per `logical_identity_key`:

```sql
SELECT revs, count(*) AS keys_with_this_many_revisions
FROM (SELECT logical_identity_key, count(*) AS revs
      FROM kb.semantic_decision_candidates GROUP BY 1) t
GROUP BY 1 ORDER BY 1;
--  1  | 91   (never superseded — healthy)
--  2  | 51
--  10 |  5
--  15 |  3
--  20 |  5
```

Thirteen `logical_identity_key`s (13 provision candidates for record 416) have 10-20 revisions
each — up to **19 dead rows behind 1 live one**. Breakdown by artifact type: 182 superseded rows
are `provision`, 51 are `metric`.

## A second, more concerning finding: at least one chain isn't accumulating genuine revisions — it's oscillating

Pulling the full revision history for one 20-revision key surfaced something that changes the
shape of this bug:

```sql
SELECT revision, status, payload_fingerprint, create_time
FROM kb.semantic_decision_candidates
WHERE logical_identity_key='provision:416:416_prv_41'
ORDER BY revision;
```

| revision | status | `payload_fingerprint` (truncated) | create_time |
|---:|---|---|---|
| 1 | superseded | `5479b117…` | 08-13 07:43:03 |
| 2 | superseded | `762bf9d7…` | 08-13 07:43:03 |
| 3 | superseded | `194f8707…` | 08-13 07:43:03 |
| 4 | superseded | `620db635…` | 08-13 07:43:03 |
| 5 | superseded | `5479b117…` | 08-13 16:20:36 |
| 6 | superseded | `762bf9d7…` | 08-13 16:20:36 |
| 7 | superseded | `194f8707…` | 08-13 16:20:36 |
| 8 | superseded | `620db635…` | 08-13 16:20:36 |
| 9-12 | superseded | same 4, same order | 08-13 16:23:48 |
| 13-16 | superseded | same 4, same order | 08-14 15:32:12 |
| 17-19 | superseded | same 4, same order | 08-14 16:09:02 |
| 20 | **candidate** | `620db635…` | 08-14 16:09:02 |

The `payload_fingerprint` cycles through exactly **four** distinct values, in the same order,
across five separate re-normalization passes — it never converges. Row 20 (the current live row)
has the identical fingerprint as rows 4, 8, 12, and 16, all already `superseded`. `Propose` only
compares a new proposal against the *immediately prior* revision
(`decision_candidates_store.go:235`, `if hasPrior && prior.PayloadFingerprint == fp`), so it has no
way to notice "this exact payload already existed three revisions ago" — it just keeps minting new
rows and superseding forward.

This means the 233-row figure is not simply "genuine content changes accumulating history" the way
the design intends — for this key, at least, `normalize_assertions` is producing a small, repeating
set of variants for what should be one stable claim about `416_prv_41`, and every re-run multiplies
dead rows without ever landing on `accepted`. **I have not root-caused why the four payloads
differ** (untouched here: whether `extract_provisions` output itself varies non-deterministically
across reruns, or whether something in `ProvisionNormalizer`'s payload construction is
order/time-dependent) — that is a separate investigation. It matters here because it means a
retention job that only prunes old rows treats a symptom; if this key gets reprocessed again, the
same four-way cycle will very likely regenerate this exact same growth pattern.

## Why this matters even though the table is small today (520 kB)

- **No consumer currently reads superseded rows for anything.** Grepped `server/api/kbhandler/`:
  no handler, no review UI, and no telemetry path (`telemetry.go:70-75` explicitly does
  `DISTINCT ON (logical_identity_key) ... ORDER BY revision DESC`, so superseded rows are already
  correctly excluded from operational reporting) ever needs a superseded row for normal operation.
  They exist purely for forensic/audit lookup, which nobody has built tooling for yet either.
- **Growth is driven by routine, expected operations, not edge cases.** Reprocessing a record is a
  first-class, documented operation (the exact record-416 bug required "record 416 must go through
  metric extraction again" as its resolution) — every reprocessing pass that changes even one
  candidate's payload creates a full new wave of revisions across every candidate whose fingerprint
  moved, whether that movement is real (a genuine value/subject change) or spurious (an
  oscillation like the one above).
- **Nothing bounds the chain length per key.** A key that's part of an unresolved bug's debugging
  loop (as `416_prv_41` clearly is) can accumulate revisions indefinitely with no cap, no alert, and
  no operator-visible signal beyond manually noticing the count.
- **The FK shape makes decision-candidates safe to prune, but assertions are not**, which matters
  for scoping any fix: `kb.assertion_evidence.assertion_id` has no `ON DELETE CASCADE`
  (`20260801000002_create_kb_assertion_evidence.sql:13`, explicitly deferred to an
  application-level cascade), so a superseded `kb.semantic_assertions` row cannot be hard-deleted
  without first deleting its evidence — deliberately, per that migration's own comment. A
  superseded `kb.semantic_decision_candidates` row has no such inbound dependents (only the
  self-referencing `superseded_by`, which points *forward* from old to new, never backward), so it
  is safe to prune without an evidence cascade.

## Recommended remediation

1. **Close the OD6 gap explicitly.** Extend ADR `2026072901` §OD6 (or add a new OD) to state a
   retention decision for `superseded` rows on both tables, not just `unsupported`/`rejected`. As
   written today, an implementer reading DR24's non-goals list would reasonably conclude no
   retention policy is needed for `superseded` — the ADR is silent, not intentionally permissive.
2. **Archive, don't hard-delete, decision-candidates.** There's a working precedent for exactly
   this shape of problem already in the codebase: ADR `2026062102` describes `deepdoc`'s
   `llm_usage_event` retention job, which deletes DB rows and archived files older than a
   configured `llm.usage_retention_days`, after copying to a compressed archive. Mirror that:
   - add a scheduled job (or an on-demand admin endpoint, matching the existing
     `drain_deferred_decisions_handler.go` pattern) that selects
     `status = 'superseded' AND modify_time < now() - retention_interval`,
   - copies matched rows to a `kb.semantic_decision_candidates_archive` table (or a
     compressed off-DB archive, matching the LLM-log pattern) for forensic lookup, then deletes
     them from the operational table.
   - Gate the interval behind a config value, e.g. `semantics.decision_candidate_retention_days`,
     analogous to `llm.usage_retention_days`.
3. **Guard the sweep against in-flight chains.** Only archive a superseded row once its
   `logical_identity_key`'s *current* (highest-revision) row has reached a stable terminal-ish
   state for the retention window — i.e., don't sweep a chain whose live head is still
   `candidate`/`in_review`/`deferred` and being actively retried, only one whose head is
   `accepted`/`rejected` or has itself been stable past the window. This avoids deleting history
   mid-debugging, which is exactly the scenario that produced the 233-row figure here.
4. **Leave `kb.semantic_assertions` superseded rows alone for now.** No superseded assertion
   exists in the live data yet, and hard-deleting one requires deleting its
   `kb.assertion_evidence` rows first (no cascade), which is a materially bigger decision — an
   accepted-then-superseded assertion is authoritative history, not a discarded proposal. Scope
   this to decision-candidates first; revisit assertions under the OD6 extension once the pattern
   is actually observed in the data.
5. **Investigate the oscillation separately before assuming a retention job alone fixes the
   growth rate.** File or extend a follow-up on why `provision:416:416_prv_41` (and likely its
   twelve siblings with 10-20 revisions) cycles through exactly four `payload_fingerprint` values
   rather than converging — check whether `extract_provisions` output is non-deterministic across
   reruns for this record, or whether `ProvisionNormalizer`'s payload construction has an
   order/time-dependent field. Until that's understood, any retention job's steady-state row count
   for actively-reprocessed records is unpredictable.

## Acceptance criteria

- ADR `2026072901` (or a successor) explicitly states a retention decision covering
  `status = 'superseded'` on `kb.semantic_decision_candidates`, closing the OD6/DR24 gap.
- A retention mechanism exists (scheduled job or admin-triggered) that removes old superseded
  decision-candidate rows from the operational table without deleting the current
  (highest-revision) row of any chain, and without archiving rows whose chain is still actively
  changing.
- Re-querying `SELECT status, count(*) FROM kb.semantic_decision_candidates GROUP BY 1` after the
  mechanism runs against record 416's data shows the `superseded` count bounded by the retention
  window, not accumulating without limit.
- The `provision:416:416_prv_41`-style oscillation is root-caused (even if the fix lands in a
  separate change) so the acceptance criterion above isn't immediately re-violated by the next
  reprocessing run.

## Still owed

- Root cause of the four-fingerprint oscillation (flagged above, not investigated here).
- Whether the other twelve 10-20-revision provision keys for record 416 show the same cyclic
  pattern or genuinely-changing payloads — only `416_prv_41` was inspected in full.
- Design for the archive table/mechanism itself (schema, job scheduling, config surface) — this
  report identifies the gap and a recommended shape, not a ready-to-implement design.

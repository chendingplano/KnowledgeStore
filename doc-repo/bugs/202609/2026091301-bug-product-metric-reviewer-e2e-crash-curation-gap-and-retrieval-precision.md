# product-metric-reviewer task 6.1 e2e: two crash/gap bugs (fixed) and a retrieval-precision defect (open)

Date: 2026-09-13

Status: `open`. Two of three findings are `fixed-verified` (see Resolution 1 and 2
below). The third (retrieval precision) got a partial, verified mitigation
(Resolution 3) — a similarity floor and product-root query anchoring are now live
and measurably remove some noise — but empirical testing against the live corpus
shows this does **not** solve the core problem for short, generic node labels: see
**Finding 3, updated** below before assuming a threshold bump will finish the job.

System: `ChenWeb` product-metric-reviewer (openspec change `product-metric-reviewer`,
task 6.1 — end-to-end verification against a real corpus)

Component: `productreviews.DocumentScoper.pathC` (`docscope.go`), `productreviews.
IntakeProductReview` (`intake.go`), `productreviews.rrfSearch` (`hybrid.go`)

Related: `ChenWeb/openspec/changes/product-metric-reviewer/` (proposal, specs,
tasks.md, notes.md), `KnowledgeStore/doc-repo/hand-offs/202609/2026090901-handoff-product-metric-reviewer.md`.

## Summary

Task 6.1 (e2e verification against a real corpus) had never actually completed: the
only real attempt on record (`kb.product_review_runs.id=1`, requested by the app's
own user against a "Ventilator" profile) failed outright with a Postgres error.
Investigating that failure surfaced three distinct problems, found in this order:

1. Every review run failed immediately with `pq: invalid input syntax for type json
   ... (22P02)`, regardless of data — a genuine crash bug.
2. Once (1) was fixed, retrieval ran but returned **no part-tier attribution** for
   any profile built through the self-service "Product Review" intake page — a
   design gap in that page, not in the curation model itself.
3. Once (1) and (2) were fixed and re-tested against a domain-appropriate profile
   (`血压计` / blood pressure monitor, matching the corpus actually loaded), roughly
   half of the part-tier attributed metrics turned out to be **wrong-domain**
   matches (e.g. a "主机" (host unit) node attributed a composting-facility chamber
   volume metric) — a retrieval-precision defect, not a crash.

## Finding 1 — Path C query crashes on any call (fixed-verified)

`docscope.go`'s `pathC` (the `document.doc_kind` standards-boost query) read:

```go
rows, err := s.DB.QueryContext(ctx, `
    SELECT record_id, COALESCE(value, '')
    FROM kb.doc_facet_values
    WHERE path = 'document.doc_kind' AND record_id = ANY($1)`, pq.Array(recIDs))
```

`kb.doc_facet_values.value` is `jsonb`. Postgres resolves `COALESCE(value, '')`'s
common type as `jsonb` and constant-folds the literal `''` into `''::jsonb` **at
parse time**, before any row is read — and `''::jsonb` is itself invalid JSON
(`invalid input syntax for type json` / `DETAIL: The input string ended
unexpectedly.`). This fails on every call, independent of whether any row is
actually NULL, which is why run 1 failed in ~0.5s having done nothing.

### How it was confirmed

Reproduced directly against `miner` by driving the real `RunController.Rerun`
through a throwaway harness (`server/cmd/debug-pmr-rerun`, not committed — see
Cleanup) with `errors.As` unwrapping the driver error: `Code: 22P02`, `Detail: The
input string ended unexpectedly.`, `Position: 38`, which lib/pq's `Error.Error()`
renders as `"at position 2:37"` (line 2, column 37 of the multi-line query text) —
landing exactly on the `''` literal in `COALESCE(value, '')`.

### Fix

`docscope.go` — unwrap the jsonb scalar to text instead of casting a literal into
it: `COALESCE(value #>> '{}', '')`. This also fixes correctness independent of the
crash: `value` for `document.doc_kind` is written as a JSON string (e.g.
`"da:doc_kind_standard"`) by `doc_facet_store.go`'s `json.Marshal`, so a bare
`value::text` cast would have kept the quotes and never matched
`standardDocKinds`'s unquoted map keys.

### Regression coverage

Not yet added — `docscope_test.go` uses sqlmock, which does not execute real SQL
against Postgres and would not have caught a Postgres-side type-cast failure.
Consider a `TEST_DATABASE_URL`-backed integration test for `pathC` (see 2026090501
for the precedent: sqlmock-level tests already existed for that bug's code too and
also would not have caught it).

## Finding 2 — self-service intake never curates, so part-tier attribution is structurally impossible (fixed-verified)

`IntakeProductReview` (`intake.go`) is the backend for the "Product Review"
self-service page (`ChenWeb/development → Applications → Product Review`). It
builds a profile and immediately marks it `ready`:

```go
if err := builder.Build(ctx, profile.ID, ProposeInput{}); err != nil { ... }
if err := store.SetProfileStatus(ctx, profile.ID, ProfileReady); err != nil { ... }
```

`Build` runs propose → ground → expand → attach-aspects. Only the aspect-attachment
step sets `status = accepted`; every LLM-proposed `module`/`part` node is left at
`status = proposed`. Retrieval (`LoadScopeNodes`, `scopenodes.go:48`) only loads
`WHERE status = 'accepted'` — by design (`specs/product-scope-profile/spec.md`:
*"Rejecting a node excludes it from later runs"*; `specs/product-artifact-retrieval
/spec.md` keys every path on *"an accepted scope node"*). So a review run through
the intake page can never produce a `part`-tier result: there is no manual curation
step in that flow to ever accept one.

This is **not** the same status field as `kb.product_names.status` (a separate,
currently-uncommitted product-name-canonicalization feature under
`server/cmd/product-names-import/` — proposed/approved gates a different table
entirely and was confirmed, by grep, to be read by no code in the review/retrieval
path).

### Fix

New `Store.AcceptAllProposed(ctx, profileID)` (`store.go`) — one-shot `UPDATE
kb.product_profile_nodes SET status='accepted' WHERE profile_id=$1 AND
status='proposed'` + one version bump, in a transaction. Wired into
`IntakeProductReview` between `builder.Build` and `SetProfileStatus(ready)`. The
manual curation page (`/home3/product-metric-review`, spec `product-scope-profile`)
is untouched — its accept/reject/edit workflow still gates normally for profiles
built that way.

### How it was confirmed

Ran the full intake flow (`CreateProfile` → `Build` → `AcceptAllProposed` →
`SetProfileStatus(ready)` → `StartReview`) through the real code, for a fresh
profile named `血压计`, via the same throwaway harness. Result: run completed,
**36 part-tier and 1 aspect-tier attributed results**, 20-entry gap list — all
three of task 6.1's literal success conditions met for the first time.

## Finding 3 — Path B's vector half has no similarity floor, so generic node labels pull in wrong-domain metrics (open)

Spot-checking the `血压计` run's part-tier results (`kb.product_review_results`,
`run_id=6`) shows real, correct matches — e.g. `气囊` (cuff bladder) ← "第二次读取的
压力示值" (second pressure reading) — mixed with clearly wrong-domain ones, e.g.:

```sql
select r.tier, n.label, m.metric_name, m.metric_subject
from kb.product_review_results r
join kb.product_profile_nodes n on n.id = r.node_id
join kb.metrics m on m.id = r.source_row_id
where r.run_id = 6 and r.tier = 'part' order by n.label limit 5;
--  part | 主机   | 单室体积             | 堆肥设施(阳光房)
--  part | 主机   | 振荡频率             | 往复式水平振荡机
--  part | 存储器 | 易腐垃圾量           | 农村地区易腐垃圾
```

`主机` ("host unit") and `存储器` ("memory/storage") are correct labels for parts of
a blood pressure monitor, but they matched composting-facility and rural-waste
metrics. `kb.metrics` (398 rows) is *not* exclusively blood-pressure-monitor
content — it has accumulated across many past sessions' unrelated document domains
(composting, fertilizer, biogas among them).

### Root cause

`rrfSearch` (`hybrid.go:67-88`) fuses a lexical CTE (`lex`, gated — it requires
`@@ plainto_tsquery` or an `ILIKE` hit) with a vector CTE (`sem`):

```go
sem AS (
    SELECT sa.artifact_type, sa.artifact_id, sa.input_record_id, ...
    FROM kb.search_artifacts sa
    WHERE sa.artifact_type = ANY($2) AND sa.embedding IS NOT NULL
    ORDER BY sa.embedding <=> $4::vector, sa.artifact_id
    LIMIT $3
)
```

`sem` has **no similarity threshold** — it always returns the `limit` (200) nearest
neighbors by raw cosine distance from the *entire* corpus, however distant they
actually are, and RRF fusion always assigns them a nonzero score. Combined with
`docscope.go`'s `pathB` sending each node's label **alone** (`n.labelText()` — no
product-root context, e.g. `血压计`) as the query text, a short generic label like
`主机` or `存储器` gets embedded and matched against the whole corpus with no floor
and no product anchor — so its "200 nearest" always includes off-domain content
when the corpus itself spans many domains, and none of it is excluded.

### Remediation implemented (2026-09-13) — partial, see empirical result below

1. **Similarity floor.** `rrfSearch` (`hybrid.go`) now takes `minSimilarity
   float64` and applies `AND (1 - (sa.embedding <=> $4::vector)) >= $6` to the
   `sem` CTE. New `ScoringConfig.HybridSimilarityMin` (`hybrid_similarity_min` in
   `product-review.local.toml`), default `defaultHybridSimilarityMin` when unset.
2. **Product-root query anchoring.** `docscope.go` `pathB` and `retrieve.go`
   `Retrieve`'s Path E hybrid sub-case both now prefix a `module`/`part` node's
   query text with the product root's label (e.g. `"血压计 主机"` not bare `"主机"`)
   before calling `rrfSearch`. This only strengthens the **lexical** half (the
   vector half still uses the node's own pre-computed embedding, unaffected by
   query-text changes — the floor is what constrains that half).

### Finding 3, updated — the floor and anchoring do not close the gap for generic labels

Re-ran the `血压计` review (request id 2) after implementing both. Result counts
were **unchanged** at `hybrid_similarity_min = 0.15` (the floor filtered nothing),
and barely moved at `0.20` (198 vs 199 attributed, one weak hit removed) — the
known false positives for `主机` (发酵周期/composting, 单室体积/composting,
振荡频率/oscillator) are **still present** at `0.20`. Root-caused precisely against
live data:

```sql
-- 主机 node (id 75) vs its 200 nearest metric neighbors by embedding:
select min(sim), max(sim), count(*) from (...) t;
--        min       |        max        | count
--  0.2306 | 0.3213 | 200

-- top-20 nearest, interleaved right-domain and wrong-domain:
--  0.267  自测自动模式 (BP self-test mode)              — right domain
--  0.260  YY 9706.230—2023 (the actual BP-monitor std!) — right domain
--  0.251  外包装箱 (packaging)                          — right domain
--  0.249  机器成肥设备 (composting equipment)           — WRONG domain
--  0.245  堆肥设施 (composting facility)                — WRONG domain
--  0.241  自动无创血压计A/B (auto noninvasive BP)       — right domain
--  0.235  往复式水平振荡机 (oscillator)                 — WRONG domain
```

True and false positives are **interleaved in the same 0.23–0.32 band** for this
2-character label — there is no threshold that keeps the right-domain hits and
drops the wrong-domain ones. A floor high enough to exclude 0.249 (composting)
would also exclude 0.241 (a real BP-monitor match) sitting right below it.

Anchoring doesn't help either, for a different, also-confirmed reason: the
wrong-domain document (`416_mtc_32`, the composting one) does not mention `血压计`
anywhere in its indexed text (`search_document ILIKE '%血压计%'` → false), so the
anchored lexical query correctly fails to match it — **but several genuine
right-domain matches for `主机` don't mention `血压计` in their own chunk's indexed
text either** (`自测自动模式持续时间阈值`, the `YY 9706.230` rows — both false on the
same check). Requiring lexical confirmation would drop those true positives too.
Root cause: per-chunk indexing does not consistently repeat the parent document's
product identity in every chunk's `search_document`, so neither the embedding nor
the chunk-local lexical text reliably carries product context for a generic label.

**This is not a threshold-tuning problem — raising `hybrid_similarity_min` further
trades false positives for false negatives on the same node, roughly 1-for-1, per
the interleaved distribution above.** A real fix needs one of:

1. Propagate `input_record_id`'s linked `kb.products` canonical name (or
   `kb.doc_facet_values`) into each chunk's indexed text or as a filterable
   column, so Path E's hybrid half can require actual product-identity
   concordance instead of raw text similarity.
2. Accept this as an inherent precision limit of short/generic node labels and
   lean on the human-reviewed report UI (evidence drawer already shows score,
   tier, and inclusion reason per result) rather than trying to fully automate it
   away — the spec's Requirement-03 already forbids restricting Path E to the
   document scope set, which rules out the most obvious alternative fix.
3. Re-run this same `主机`/`存储器` distribution query after any future indexing
   change to confirm the interleaving is actually resolved, not just shifted.

The floor and anchoring are not wasted — they measurably cut the *extreme* long
tail (results changed at `0.20` vs `0.15`) and are real, tested infrastructure for
whichever of (1)/(2) above gets picked. They just don't, by themselves, solve the
`血压计`/`主机` case documented here.

## Acceptance criteria

- `pathC` and the intake auto-accept fix: any review run against a `ready` profile
  built through *either* the manual curation page or the self-service intake page
  completes (`status=completed`) and can produce `part`-tier results when the
  profile has grounded parts — met, see Resolution 1/2.
- Retrieval precision (Finding 3): a `part`-tier or `aspect`-tier result's source
  document is plausibly about the product the profile represents, checked by
  re-running the `血压计` review after remediation (1)/(2) and spot-checking that
  the composting/fertilizer/biogas-domain matches no longer appear for `主机` /
  `存储器`.

## Cleanup

Two throwaway harnesses were written for this investigation and deleted before
committing: `server/cmd/debug-pmr-rerun/` (Findings 1/2) and
`server/cmd/debug-pmr-verify/` (Finding 3's re-runs). Neither is part of the
product code or this commit.

## Resolution 1 — Finding 1, `docscope.go` pathC crash (2026-09-13)

Fixed as described above. Verified by re-running `RunController.Rerun` against the
real `miner` database through the harness: run completed with 222 results (93
attributed, 129 document-scope) instead of failing in 0.5s.

## Resolution 2 — Finding 2, intake curation gap (2026-09-13)

Fixed as described above (`Store.AcceptAllProposed` + `intake.go` wiring). Verified
by running the full intake flow for a fresh `血压计` profile end to end: 36
part-tier + 1 aspect-tier attributed results, 20-entry gap list.

## Resolution 3 — Finding 3, retrieval precision (2026-09-13, partial)

Implemented the similarity floor and product-root anchoring described above.
Verified against the live `血压计` review (re-run three times at `hybrid_similarity_
min` 0 → 0.15 → 0.20): the mechanism works as built and does remove weak hits (198
vs 199 attributed, one hit demoted at 0.20), but does **not** close the false-
positive gap for generic short labels — see "Finding 3, updated" above for the
full evidence. **This finding stays open.** Closing it needs the product-identity
propagation described in remediation option (1), which is a larger change (touches
the indexing pipeline, not just retrieval) and was not attempted here.

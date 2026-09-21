# Open Bug Loops

Bug docs that are **not** in a terminal state. A bug doc explains what was
already done; it has no open/closed state of its own, so anything still owed —
an unrun verification, a deferred fix, a known-but-unfixed defect — is listed
here or it is forgotten.

Terminal (do not list here): `fixed-verified`, `wontfix`.
Listed here: `open`, `fixed-unverified`, or any doc with a "still worth doing".

Set `Status:` in the doc's header block. Remove the doc from this list when it
reaches a terminal state.

## Open

- [2026092201 — merged pass returned 0 rows for every chunk and wiped record 416](202609/2026092201-bug-merged-pass-returns-zero-rows-and-wipes-record.md)
  — `fixed-unverified`. The first `EXTRACT_PRODUCTS_MERGED_PASS=true` run sent Pass 1's
  `{"mentions":[...]}` schema as its task suffix, overriding the merged prompt's own
  `{"products":[...]}` schema; the model complied, `payload["products"]` was absent, and
  all 10 chunks yielded 0 rows. `productExtractionContract` accepts either key, so nothing
  errored. The force-delete-then-save path then deleted record 416's 1219 rows, inserted
  0, and recorded `proc_status=success`. Fixed with a `products`-pinning task suffix, a
  shape guard, and an all-chunks-failed guard; verified by replaying the 10 archived
  requests (172 rows returned). Still owed: **re-run record 416** (its rows are gone and
  its search index was cleared); decide whether a zero-row save should ever be allowed to
  replace a non-empty record, which is not merged-specific.

- [2026092105 — extract_products extracts facilities/works as products, and mines product names out of normative-reference titles](202609/2026092105-bug-extract-products-extracts-facilities-and-mines-citation-titles-as-products.md)
  — `fixed-unverified`. Two precision defects in Pass 1, the pipeline's only producthood
  gate: (a) no exclusion for places/facilities/construction works, so 垃圾转运站,
  生活垃圾焚烧厂, 垃圾分类投放点, 环境卫生设施 etc. became products — 128 of record 416's
  1219 rows, all typed `system`; (b) product names mined out of 规范性引用文件 citation
  titles (28 rows), with Pass 2 fabricating a `requirement_text` to justify them.
  Pass 2's prompt explicitly forbade re-deciding producthood, making both unrecoverable.
  Fixed at the prompt layer (`prompt-extract-product-mentions-v2.md` +
  `prompt-enrich-product-mention-v4.md` narrow veto); A/B on record 416 gives
  facility mentions 13 → 0 with distinct mentions up 140 → 154. Still owed: the user's
  re-run of record 416 and post-run confirmation that `prompt_name` reads v4 (a stale
  `mise.local.toml` pin silently overrode the Go default before — the 2026-09-20 run used
  v2 while the default was v3); commit in both repos; decide on the 34 facility-shaped
  `proposed` rows already in `kb.product_names`; size historical blast radius.

- [2026092103 — extract_products Pass 2 prompt generated two fully-discarded output blocks per row, and had drifted from a dead single-pass prompt file](202609/2026092103-bug-extract-products-pass2-wasted-output-tokens-and-prompt-drift.md)
  — `fixed-unverified` for the confirmed part. On record 416 (12 pages), `extract_metrics` +
  `extract_products` totaled 3,310,666 output tokens (~¥14), attributed mainly to
  `extract_products` — by candidate 26 of Pass 2 alone, 1011 rows had already been produced
  (~39 rows/candidate). Root cause: the live Pass 2 prompt (`prompt-enrich-product-mention-v2.md`)
  asked for `discriminators`/`discriminators_en` (never read by any Go code) and every `_en`
  field (unconditionally overwritten by Pass 3a for every row) — both pure waste, same defect
  class as the `category_paths` leak already fixed 2026-09-12. Along the way, found and the
  user deleted an unrelated dead prompt file (`prompt-extract-products-v1.md`, a pre-refactor
  leftover never wired into the pipeline) that had caused the original "isn't Pass 2 redundant
  with Pass 1" confusion. Fixed in the working tree: new `prompt-enrich-product-mention-v3.md`
  (default, drops both wasted blocks, documents the per-call `Candidate:` append, adds a
  `related_products` scoping rule and an anti-padding instruction), `output_tokens` added to
  Pass 2's per-candidate log line, spec updated. `go build`/`go test` clean. Still owed: commit
  (both `ChenWeb` and `KnowledgeStore`), a live re-run on record 416 to confirm actual token
  savings, a decision on the other orphaned prompt file
  (`prompt-enrich-product-relations-v1.md`), and root-causing whether the row-count explosion
  itself (independent of the wasted fields) is expected recall or a separate over-generation
  defect.

- [2026092101 — `llm_usage_event` logged with null `user_id`/`record_id`/`run_id` for two independent doc-processing call paths](202609/2026092101-bug-llm-usage-event-missing-attribution-user-record-run-id.md)
  — `open`. Bug 1: every JSON-extraction LLM call (23 call sites via `newLLMJSONInput`) had
  `user_id` NULL for the table's entire history — doc-processing never had a context-carrying
  mechanism for it, only for `record_id`/`run_id`. Bug 2, structurally separate: every
  embedding call (`embed_metric`, `embed_product`, `embed_topic`, `embed_summary`, query
  embedding, inventory-category embedding) had `user_id`, `record_id` **and** `run_id` all
  NULL — the shared library's `EmbedInput`/`EmbedBatchInput` didn't even have `RecordID`/
  `RunID` fields, and none of the 6 call sites read `ctx` at all. Both root-caused and fixed
  in the working tree this session (design: event generators supply `user_id`, doc-processing
  only extracts it, generators alarm on a missing one; embedding calls now read attribution
  from `ctx` the same way extraction calls do). `go build`/`go test` clean for every touched
  package in both `shared/go` and `ChenWeb`. Still owed: commit (currently uncommitted in both
  repos), `go work sync` + rebuild against the published shared-lib version, and live
  verification against a real rerun — nothing was confirmed beyond mocked-DB unit tests. No
  backfill of existing null rows, per explicit instruction. `doc-reviews` has the identical
  Bug-1-shaped gap, deliberately not fixed here (out of scope); the fully-automated
  file-converter trigger path still has no `user_id` source at all, caught only by the
  generic insert-time alarm, not a generation-time one.

- [2026091301 — product-metric-reviewer task 6.1 e2e: two crash/gap bugs (fixed) and a retrieval-precision defect (open, deeper than a threshold)](202609/2026091301-bug-product-metric-reviewer-e2e-crash-curation-gap-and-retrieval-precision.md)
  — `open`. Two of three findings fixed-verified same day: (1) `docscope.go` pathC's
  `COALESCE(value, '')` against a `jsonb` column crashed every review run outright
  (`''::jsonb` is invalid JSON), fixed via `value #>> '{}'`; (2) the self-service intake page
  (`IntakeProductReview`) never curated its proposed module/part nodes, so part-tier
  attribution was structurally impossible via that flow — fixed with new
  `Store.AcceptAllProposed`, wired into intake only (manual curation page untouched). Still
  open, now with a partial mitigation shipped: (3) `rrfSearch`'s vector half had no similarity
  floor — added one (`ScoringConfig.HybridSimilarityMin`) plus product-root-anchored query
  text for module/part nodes, both verified live. But re-running against the corpus proved
  this does **not** fix precision: for a short generic label like `主机`, real and wrong-domain
  matches are interleaved in the same 0.23–0.32 cosine-similarity band (measured, not
  estimated) — no threshold separates them, and the wrong-domain documents don't lexically
  co-occur with the product name either (confirmed per-chunk). A real fix needs
  product-identity propagated into the chunk-level index, which is a larger change than this
  bug's scope — not attempted.

- [2026082101 — auto-promoted metric_definition terms conflate metric-only fields with the generic term schema and drop available data](202608/2026082101-bug-auto-promoted-ontology-terms-schema-and-data-loss.md)
  — `open`, root-caused, not yet fixed. Three confirmed defects in ADR 2026081201's auto-promotion
  path: `definition` is bound to `formula_or_definition` (often legitimately blank) instead of the
  descriptive `metric_desc`, which exists and is never read; `value_type`/`range_type`/
  `permitted_unit_term_ids` are metric-only flat columns dead for the other 7 term kinds, with no
  general `properties` bag (the QUDT importer's `symbol`/`deprecated` payload has the same
  homeless-data problem); and a resolved unit can still be lost with no raw-text fallback field —
  confirmed on live row `measurement:kwc_bb95850b160d`, whose metric had unit `%` and a matching
  released `quantity:unit_PERCENT` term, yet `permitted_unit_term_ids` is empty. Compounding factor:
  `EnsureAcceptedOrCreate` never refreshes an existing auto-promoted term, so a term stays frozen on
  whatever its first-ever triggering metric looked like even after reprocessing improves the data.

- [2026081802 — review of ADR 2026081701 (ontology object classes, metric instances, relations)](202608/2026081802-bug-adr-2026081701-canonical-metric-classes-review.md)
  — `open`, review only; 11 findings numbered Issues 16–26 continuing the ADR's own 01–15
  sequence. Architecture and the §2.1 production survey verified correct (182/55/45/7 exact).
  Blocking-ish: three pre-existing columns whose meaning the new model changes without naming
  them — `semantic_assertions.logical_identity_key` vs the new claim registry (I16), revision
  semantics under find-or-create (I17), and the `status` state machine, which has no legal value
  for "persisted but unendorsed" (I21). Also: the one-current-evidence-link invariant is asserted
  in three places across two ADRs but has no constraint and is already violated in `miner` (I18);
  `kb.ontology_term_redirects` is depended on by four decisions and created by none (I19);
  autonomous exact merges collide with `ontology_mappings.approval_status` + spec §9.1 (I20);
  and DR8 disagrees with ADR 2026081801 DR6 on the assertion's state field set (I22). Largest
  finding is I24 — the semantic path has run on 1 of 58 input records, so the ~100× assertion
  growth, provisional-class-as-norm, and per-class fan-out consequences are undrawn.

- [2026081602 — ChenWeb admin pages surface a raw 401 error instead of redirecting to /login](202608/2026081602-bug-chenweb-401-no-redirect-to-login.md)
  — `open`, root-caused, fix scoped, not yet implemented. Two gaps: `checkAuthStatus()` in
  `shared/svelte/stores/auth.svelte.ts` never redirects on a failed `/auth/me` check, and 11
  near-identical `req<T>()` fetch helpers across `ChenWeb/web/src/lib/components/home3/*-client.ts`
  (plus `userManagementService.ts`) throw a plain `Error` on any 401 that the calling page renders as
  a banner. `dbstore.ts`'s `checkSystemResp` has the same gap for `db_store` consumers app-wide.
  Recommended fix: one shared `redirectToLoginIfUnauthorized` helper in `shared/svelte`, wired into
  all of the above. Open questions: redirect-back URL, whether `tax` shows the same symptom, whether
  `CustomHttpStatus.NotLoggedIn` (557) should also redirect.
- [2026081301 — production `associate_semantics` has no released measurement vocabulary](202608/2026081301-bug-production-semantic-association-missing-measurement-vocabulary.md)
  — `miner` contains auto-promoted metric-definition terms but no curated
  `measurement` module release or released `mea:*` assertion vocabulary. Normal
  services use `miner`; ontology bootstrap is separate and the standalone seed
  CLI has a `PG_USER`/`PG_USER_NAME` mismatch plus a `chenweb_test` default.
  Existing governed-term deferrals also lack a retry drain.

## Resolved (2026-08-03)

- [2026080301 — SemOS P5 rule-driven routing declared complete but is not finished](202608/2026080301-bug-ontology-p5-rule-driven-routing-not-finished.md)
  — `resolved (superseded by 2026080302; remediation 2026080303, log 2026080304)`.
  Removed from Open: the full-completion/correctness audit of P5 was consolidated into review
  `2026080302`, and every finding was addressed by the completion plan `2026080303` (Chunks A–H,
  merged to `main` and pushed): the resolver is wired and flag-gated, promotion is transactional
  with canonical checksums, clearance keys on `document.doc_kind`, exit criteria point at real
  tests. The only remaining item is I2 (live Postgres proof), which the audit itself confirmed is
  genuinely deferred — tracked in plan `2026080303`, not as an open bug.

## Open

- [2026081101 — kb.ontology_candidates fingerprint dedup is exact-match only](202608/2026081101-bug-ontology-candidates-fingerprint-dedup.md)
  — `fixed-unverified`. Reprocessing input_record 416 produced two near-duplicate
  `metric_definition` candidates (ids 16, 17) that weren't deduped because `label` and the sole
  `alias` swapped between extraction runs, changing both the fingerprint and the derived
  `term_id`. Fix implemented same day as ChenWeb openspec change `ontology-candidate-dedup`:
  `candidates.IdentityKey` (module + term_kind + normalized `{label} ∪ aliases`) plus soft
  `candidate_matches` recording in `CandidateStore.CreateCandidate`, migration
  `20260811000005` applied live, all 17 tasks done, unit-tested. Still owed: live end-to-end
  verification (reprocess a real document and confirm `candidate_matches` populates, not just the
  sqlmock unit tests) and a backfill decision for the pre-existing rows 16/17 themselves, which
  won't retroactively match each other since `identity_key` is computed at insert time only.
- [2026081001 — kb.pipelines vs kb.pipeline_policies schema semantics Q&A](202608/2026081001-bug-pipeline-policies-vs-pipelines-schema-review.md)
  — `open`. Discussion ahead of a frontend pipeline-policy management page. One change agreed
  (add `kb.pipeline_policies.description`) but not yet built. Still genuinely open: `kb.pipelines`
  rows are fully mutable in place (add or remove processors, or delete the row) with **zero audit
  trail** — no asymmetric add-only restriction was found, contrary to an initial assumption.
  Needs a decision between making `kb.pipelines` immutable/versioned vs. mutable-but-audited
  before the frontend's pipeline-edit UI is built. Also confirmed `kb.pipeline_policies.checksum`
  hashes the *entire* `kb.pipelines` table (not just the policy's own referenced pipelines), so
  any pipeline edit anywhere changes what a recompile of any policy's checksum would produce —
  though in practice nothing ever recompiles/compares an already-activated policy's checksum, so
  this is currently inert rather than actively broken. Worth revisiting the checksum's scope
  alongside the immutability decision.
- [2026073003 — extract_metrics recall investigation wrap-up: final state and disposition](202607/2026073003-bug-extract-metrics-recall-investigation-wrapup.md)
  — `open, paused by decision`. Closes out the three-stage investigation started in
  2026073001/2026073002. One root cause fixed with high confidence (scope-language
  misclassification, validated non-contaminated at `v8`/`v9`: 3/4→4/4 on `resolution`).
  A second partially fixed (heading misclassification interacting with a real
  recall-consistency problem on `alarm`: 2/4 historical → 3/4 under `v9`, not yet
  reliable). A third — clauses failing in correlated pairs across identical calls —
  observed twice independently, still unexplained. Per explicit user decision, this
  line of investigation is paused here; `v9`/`v4` are NOT promoted to production
  (`mise.local.toml` still pins `v4`/`v2`) pending validation against all 9 fixture
  documents, which was never run. That full-corpus validation is the concrete item
  still owed if this is picked back up.
- [2026073002 — reframing extract_metrics instability with required-vs-best-effort coverage scoring](202607/2026073002-bug-extract-metrics-required-vs-best-effort-coverage-scoring.md)
  — `open`, follow-up to 2026073001. Added `gold.toml`'s `expectation` field (19
  qualitative clauses marked `best_effort`) and `coverage.go`'s `ScoreCoverage`
  judgement (`captured`/`missing_required`/`missing_best_effort`), tested against
  2026073001's own 4 real runs. Rescoring isolates the real, still-open problems:
  `resolution` (`limit_absent`) failed 4/4, `alarm` succeeded only 2/4 — everything
  else was acceptable best-effort variation. Awaiting review on: whether
  `cl:ent-readability-1m` is correctly best_effort, the resolution/alarm fixes
  themselves, and whether `captured` should later split into correct/incorrect.
- [2026073001 — `extract_metrics` recall is unstable across identical, temperature-0 repeated calls](202607/2026073001-bug-extract-metrics-recall-instability-across-identical-calls.md)
  — `open`. Four repeats of the same document/prompts produced 4/6/8/4 metric rows.
  One clause (`resolution`, `limit_absent`) failed 4/4 — the most reproducible failure
  in the dataset. Two clause pairs succeeded/failed together across all 4 runs,
  suggesting the noise may cluster by processing unit rather than being independent
  per-clause. Also found and isolated a separate `gold.toml` fixture defect (a merged
  clause text) unrelated to the model. Temperature is already 0 and not configurable —
  ruled out as the cause. See 2026073002 for a rescoring that isolates which findings
  here are still real defects vs. acceptable best-effort noise.
- [2026071404 — doc-structure line cards ignore light mode](202607/2026071404-bug-doc-structure-line-cards-ignore-light-mode.md)
  — `fixed-verified`, and the content-column audit that 2026071403 opened is now
  **closed**: all nine `/home3` host views have been swept and tokenized. Still
  owed: every view was verified with empty/error data (the browser session was
  unauthenticated, so `kb.inputs` returned `500`). The dialogs, tables, chunk
  cards and document frames were probed for computed values through the real
  cascade, but never seen populated with a real record.
- [2026071405 — kb.inputs search dialog owns a dark palette instead of inheriting one](202607/2026071405-bug-kb-input-search-dialog-ignores-light-mode.md)
  — `fixed-unverified`. The dialog reached from the `Search` button (noted open in
  2026071403/404) now takes a `darkMode` prop and inherits host tokens via `--sd-*`
  aliases; builds and type-checks. Still owed: browser verification of the
  data-populated surfaces (results table, record-detail dialog), which need an
  authenticated backend — `kb.inputs` returns `500` unauthenticated.
- [2026071701 — Chinese doc review report shows English-duplicate and internal-context metric fields](202607/2026071701-bug-metric-cn-report-shows-english-and-context-fields.md)
  — `fixed-unverified`. `metricFieldRows` in `typst_report.go` now skips
  `MetricNameEn`/`SubjectEn`/`Description`/`DescriptionEn`/`Context`/`ContextEn`/`UnitEn`
  for the Chinese report; `go build`/`go test ./api/doc-reviews/...` pass. Still
  owed: regenerate a real report and visually confirm the seven fields are gone
  from `-report-cn.pdf` and the English report is unaffected.
- [2026071901 — DeepSeek `deepseek-v4-flash-300` llm usage events logged without account/profile linkage](202607/2026071901-bug-deepseek-llm-usage-account-profile-not-resolved.md)
  — `fixed-unverified`. Data-only fix: inserted the missing
  `llm_account_model_profile` row under the account holding the current
  `.models.toml` API key; the `resolveAccountProfileIDs` join was re-run
  directly and now resolves. Still owed: confirm against a live
  `MID-CWB-ENTITY-RELATION` call that the WARN stops and the resulting
  `llm_usage_event` row has non-null `account_id`/`profile_id`.

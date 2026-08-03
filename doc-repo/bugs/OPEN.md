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

- [2026080301 — SemOS P5 rule-driven routing declared complete but is not finished](202608/2026080301-bug-semos-p5-rule-driven-routing-not-finished.md)
  — `open`. Full-completion and correctness audit of P5 against ADR 2026072901 / spec
  2026080102 / plan 2026080103. Structural gaps: only chunks A–F are on `main` (G/H/I plus a
  large "fixing P5 implementation bugs" commit are unmerged floating commits); Chunk G
  (`classify_document`) is dead code in production (`ControlService.Resolver` never set, zero
  non-test callers, `runID=0` + empty sample at the one call site, `VocabularyReleaseID=0`);
  Chunk H promotion is non-operational (runs after `CreateRelease` commits, never on activation,
  targets a release id no proposal can reference, non-canonical predicate checksums). Correctness
  defects in wired code: legacy migrated binding checksum is md5 at runtime vs SHA-256 at compile
  so such bindings can never be cleared (criterion 16); `semrules` all/any masking is
  order-dependent and over-reports decision-relevant missing paths (spurious classifier calls);
  `frozenSubjectFacts` matches by DocumentID only (multi-target scopes gate against the wrong
  target); indeterminate-only profiles are never pinned so their closed dimensions silently
  produce no findings; gate block mode and run-scoped overrides are unreachable/dead. P5-specific
  tests all pass; I2 (live Postgres proof) genuinely deferred. Six-step remediation list in the
  doc.
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

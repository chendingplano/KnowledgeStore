# `public.llm_usage_event` rows logged with null `user_id`/`record_id`/`run_id` for two independent call paths in ChenWeb doc-processing

Date: 2026-09-21

Status: open — both root-caused, both fixed in the working tree, neither committed nor
verified live yet.

Scope: `shared/go/api/llm` (`usage_capture.go`, `openai_client.go`) plus
`ChenWeb/server/api/doc-processing` (`llm_capture_input.go`, `event.go`,
`start_doc_processing_event.go`, `control.go`, `search_indexing.go`,
`search_indexing_embedding.go`, `fix-size-chunking.go`, `inventory_category_curation.go`)
and `ChenWeb/server/api/jetstreamhandler/handler.go` (the manual-trigger admin endpoint).
`ChenWeb/server/api/llmusage/sink.go` (the DB writer) and its tests were also touched, as
a safety net, not as the root-cause fix.

Code read: `shared/go/api/llm/usage_capture.go` (`captureUsageRecord`, `NewUsageCaptureRecord`),
`shared/go/api/llm/types.go` (`Request`, `UsageCaptureInput`),
`shared/go/api/llm/openai_client.go` (`JSONExtractionInput`, `captureUsage`; `EmbedInput`,
`EmbedBatchInput`, `Embed`, `EmbedBatch`, `embedRequest`, `captureEmbeddingUsage`),
`ChenWeb/server/api/llmusage/sink.go` (`Sink.Capture`, the actual `INSERT INTO
llm_usage_event`), `ChenWeb/server/api/doc-processing/llm_capture_input.go`
(`withLLMRecordID`/`withLLMRunID`, `newLLMJSONInput`),
`ChenWeb/server/api/doc-processing/control.go` (`handleEvent`, `HandleStartDocProcessingEvent`,
`buildLineFileGeneratedPayload`, `withRunID`), `ChenWeb/server/api/doc-processing/event.go` and
`start_doc_processing_event.go` (`LineFileGeneratedEvent`, `StartDocProcessingEvent`,
`ParseLineFileGeneratedEvent`, `ParseStartDocProcessingEvent`),
`ChenWeb/server/api/jetstreamhandler/handler.go` (`PublishEvent`, `validateSubjectPayload`,
`normalizeSubjectPayload`), `ChenWeb/server/api/doc-processing/search_indexing.go`
(`replaceRegistryRows`, `ReindexMetricSearchForRecord`, `ReindexProductSearchForRecord`),
`ChenWeb/server/api/doc-processing/search_indexing_embedding.go` (`embedRegistryRows`,
`embedRowBatch`, `embedPreparedRegistryRows`, `embedWithRetry`, `embedBatchWithRetry`,
`embedQueryText`), `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
(`embedAndWriteTopics`, `embedAndWriteSummaries`), `ChenWeb/server/api/doc-processing/
inventory_category_curation.go` (`InventoryCategoryCurator.embed`), migration
`ChenWeb/project_migrations/20260920000001_llm_usage_user_and_dual_billing.sql` (added
`llm_usage_event.user_id`, the column that surfaced Bug 1).

Evidence:
```
psql miner: SELECT count(*), count(user_id) FROM public.llm_usage_event WHERE run_id=143;
  count | non_null_user_id
  ------+------------------
     310 |                 0

psql miner: SELECT user_id, call_loc, count(*) FROM public.llm_usage_event
            WHERE user_id IS NOT NULL GROUP BY user_id, call_loc;
  (0 rows)   -- every row in the table's entire history had user_id = NULL

User's own manual doc-processing run on record 416, run_id=143, 2026-09-20 18:24: all 310
llm_usage_event rows for that run have user_id NULL. Separately reported same day: embedding
calls with call_reason 'embed_metric' and 'embed_product' in the same doc-processing request
have run_id, user_id AND record_id all NULL, unlike the extraction calls in the same run.
```

Related: none yet — first doc on this topic. Migration `20260920000001` (adding the
`user_id` column) landed the same day this bug was found, per the user's own report of having
asked for it "yesterday" (2026-09-20 relative to this doc's 2026-09-21 date).

---

## 1. Summary

Two independent, non-overlapping gaps in the same feature (attributing every
`llm_usage_event` row to a user/record/run) inside ChenWeb's doc-processing pipeline:

- **Bug 1**: every LLM call made through the JSON-extraction path (`extract_metrics`,
  `extract_provisions`, `extract_products`, etc. — 23 call sites via `newLLMJSONInput`) was
  logged with `user_id = NULL`, because nothing in doc-processing had ever threaded a user
  id anywhere — not even a context-carrying mechanism for it existed, unlike `record_id`/
  `run_id`, which already had one.
- **Bug 2**: every LLM *embedding* call made by doc-processing (`embed_metric`,
  `embed_product`, `embed_topic`, `embed_summary`, ad-hoc query embedding, inventory-category
  embedding — 6 call sites) was logged with `user_id`, `record_id` **and** `run_id` all
  `NULL` — a structurally separate gap, since it's a completely different code path from
  JSON extraction and the embedding input structs in the shared library didn't even have
  `RecordID`/`RunID` fields to carry them.

Both were root-caused and fixed in the working tree this session (not committed, not
verified against a live rerun — see §5).

## 2. Root cause

### Bug 1 — `user_id` null for every JSON-extraction LLM call

`ChenWeb/server/api/doc-processing/llm_capture_input.go` had `withLLMRecordID`/
`withLLMRunID` context helpers, read by `newLLMJSONInput` (the single choke point all 23
extraction call sites go through) to populate `llmclients.JSONExtractionInput.RecordID`/
`.RunID`. There was no `withLLMUserID` counterpart at all, so `JSONExtractionInput.UserID`
was always the zero value, which `shared/go/api/llm/openai_client.go`'s `captureUsage`
faithfully passed straight through to `UsageCaptureInput.UserID` and then to the `INSERT`.
The shared library's own plumbing (`Request.UserID` → `UsageCaptureInput.UserID` →
`llmusage.Sink.Capture`'s `$4` parameter) was already correct and is unrelated to the bug —
confirmed by the fact that request-scoped callers outside doc-processing (image generation,
the agent-chat gateway) already populate `RequestCapture{UserID: ...}` from the authenticated
HTTP session and log correctly.

The deeper reason nothing could populate it: doc-processing's manual trigger runs as an
async NATS/JetStream consumer (`server/cmd/doc-processor`) with no authenticated request in
that path — there was no source of "who" to attach, and the generic admin publish endpoint
(`jetstreamhandler.PublishEvent`, `POST /api/v1/jetstream/events`, the actual path the user's
manual run on record 416 went through) published its triggering event with no `user_id`
field for doc-processing to extract.

### Bug 2 — `user_id`/`record_id`/`run_id` all null for embedding calls

Structurally separate from Bug 1's fix, because embedding goes through `Embed`/`EmbedBatch`,
not `newLLMJSONInput`:

1. **Shared library gap**: `shared/go/api/llm/openai_client.go`'s `EmbedInput`/
   `EmbedBatchInput` had a `UserID` field but **no `RecordID`/`RunID` fields at all** — even a
   caller that wanted to supply them had nowhere to put them. `captureEmbeddingUsage` built
   `UsageCaptureInput{...}` without `RecordID`/`RunID`, and called
   `captureUsageRecord(ctx, Request{}, ...)` with an **empty** `Request{}` — so
   `captureUsageRecord`'s own `req.RecordID`/`req.RunID` fallback logic (in
   `usage_capture.go`) had nothing to fall back to either.
2. **Caller gap**: none of the 6 embedding call sites in `ChenWeb/server/api/doc-processing`
   (`embedWithRetry`/`embedBatchWithRetry` in `search_indexing_embedding.go`, used by
   `embed_metric`/`embed_product`/etc.; `embedQueryText`; `embedAndWriteTopics`/
   `embedAndWriteSummaries` in `fix-size-chunking.go`; `InventoryCategoryCurator.embed` in
   `inventory_category_curation.go`) ever read from `ctx` at all — despite
   `llmUserIDFromContext`/`llmRecordIDFromContext`/`llmRunIDFromContext` already existing
   (added for Bug 1's fix, and pre-existing for `RecordID`/`RunID`) and `ctx` being threaded
   as the first parameter through every one of these functions. The fields were simply never
   read out of it.

## 3. Blast radius

Bug 1: every row ever written to `public.llm_usage_event` by doc-processing's JSON-extraction
path — confirmed by the live query in Evidence showing zero non-null `user_id` rows in the
table's entire history, not just run_id=143. Doc-reviews (`server/api/doc-reviews`) shares the
same `withLLMRunID`/`newLLMJSONInput`-shaped gap for `user_id` (has `RunID` wired, e.g.
`review-document.go:1279`, but no `user_id` equivalent) — **not fixed in this pass**, noted
as a follow-up in §6.

Bug 2: every embedding call doc-processing has ever made — `embed_metric`, `embed_product`,
`embed_topic`, `embed_summary`, `embed_provision`/`embed_summary`-adjacent artifact types that
route through the same `embedRegistryRows`, ad-hoc search-query embedding
(`EmbedSearchQuery`), and inventory-category curation embedding.

## 4. Fix implemented (uncommitted)

**Bug 1** — event generators supply `user_id`; doc-processing only extracts it; alarms fire
at generation time (this design was a deliberate choice, made with the user, over two
alternatives — a fixed "operator id" default, or attributing to `kb.inputs.owner` — the
latter was ruled out because `owner` is NULL workspace-wide, including for record 416
itself):

- `LineFileGeneratedEvent`/`StartDocProcessingEvent` (`event.go`,
  `start_doc_processing_event.go`) gained a `UserID` field, parsed from the payload's
  `user_id`.
- New `withLLMUserID`/`llmUserIDFromContext` in `llm_capture_input.go`, mirroring the
  existing run_id pattern; `newLLMJSONInput` now stamps it onto every extraction call.
- `control.go`'s `handleEvent` tags `ctx` with the event's `user_id` as early as possible;
  `buildLineFileGeneratedPayload` forwards it when `StartDocProcessingEvent` fans out into
  per-record events.
- `jetstreamhandler.PublishEvent` (the actual manual-trigger endpoint, auth-gated) now
  auto-fills `user_id` from the authenticated session for the two doc-processing trigger
  subjects, and raises an alarm (`alarms_errors`, kind `missing_user_id`) if it's still
  empty after publish — new `docprocessing.RoutingAlarmKindMissingUserID` constant.
- `llmusage/sink.go` gained a safety-net alarm (also `alarms_errors`, kind
  `missing_user_id`, deduped by `run_id`/`record_id` the same way routing alarms are) on
  **any** insert with a null `user_id`, regardless of caller — this is the one piece that
  covers call paths not otherwise touched, e.g. the fully-automated file-converter pipeline
  (`server/api/file-converters/service.go`'s `emitLineFileGeneratedEvent`), which still has
  no user source today and was deliberately left alone (see §6).
- 6 pre-existing stale tests in `sink_test.go` (SQL-expectation regexes hadn't been updated
  for the `user_id` column migration) and one signature break in `jetstreamhandler`'s test
  were fixed as a byproduct of touching this code, not as new coverage.

**Bug 2**:

- `shared/go/api/llm/openai_client.go`: added `RecordID`/`RunID` to `EmbedInput`/
  `EmbedBatchInput`; refactored `embedRequest`/`captureEmbeddingUsage`'s parameter list into
  a new `embedCallIdentity` struct (positional args were already at the practical limit) so
  `UserID`/`RecordID`/`RunID` reach `UsageCaptureInput` the same way the extraction path does.
- `search_indexing.go`'s `replaceRegistryRows` now stamps `record_id` onto `ctx` before
  embedding, since the metric/product/etc. reindex functions don't otherwise guarantee it's
  present at that call depth.
- All 6 embedding call sites listed in §2 now populate `UserID`/`RecordID`/`RunID` (or just
  `UserID`/`RunID` where `RecordID` was already a direct function parameter, e.g.
  `embedAndWriteTopics`/`embedAndWriteSummaries`) from `ctx`.

Verification done this session: `go build ./...` clean in both `shared/go` and `ChenWeb`;
`go test ./...` passes for every touched package in both modules (`shared/go/api/llm`,
`ChenWeb/server/api/doc-processing`, `ChenWeb/server/api/jetstreamhandler`,
`ChenWeb/server/api/llmusage`); one `TestMetricsProcessor_Pass1ConcurrencyBound` flake seen
once, reproduced-passing 3/3 on rerun, judged pre-existing timing flakiness unrelated to
this change. The two `llmreporthandler` test failures present before and after this change
(`TestLoadModelAPIKeyOptionsMapsDeepSeekProAliasToProModel`,
`TestListModelActivityReportsFiltersSelectedAliasToItsModel`) are unrelated — that package
was never touched.

## 5. Tasks

- [x] Root-cause Bug 1 (`user_id` null for extraction calls)
- [x] Root-cause Bug 2 (`user_id`/`record_id`/`run_id` null for embedding calls)
- [x] Implement fix for Bug 1
- [x] Implement fix for Bug 2
- [x] `go build ./...` + `go test ./...` clean in `shared/go` and `ChenWeb` for every touched
      package
- [ ] Commit both changes via `jj` — **currently uncommitted** in both `shared/go` (working
      copy `@ b9574e602444`, on top of `c7a65d662244 feat: centralize AI provider transports`
      / `1c8da6af6524 feat: attribute LLM usage to users`) and `ChenWeb` (working copy
      `@ daa1a3789365`, on top of `f41765e7d983 fix: allow decimal total spending`) — per this
      workspace's convention, the shared-library change and the ChenWeb application change
      should be two separate commits
- [ ] `go work sync` from the workspace root after the `shared/go` commit lands, then rebuild
      `ChenWeb` against the published shared-lib version (this session worked entirely via
      `go.work`'s local-replace, which is correct for dev but not a substitute for the
      publish step)
- [ ] Live verification: rerun a doc-processing pass on a real record (e.g. reprocess 416
      again) and confirm `llm_usage_event` rows for that run have non-null `user_id` for
      extraction calls, and non-null `user_id`/`record_id`/`run_id` for `embed_metric`/
      `embed_product` calls specifically — nothing in this session confirmed the fix against
      a live rerun, only unit tests with mocked DB layers
      (`sqlmock`)
- [ ] Verify the new `alarms_errors` (kind `missing_user_id`) alarm actually fires end-to-end
      against a live NATS+Postgres stack — the alarm-writing code paths were not exercised by
      any test in this session

## 6. Open questions / future related activities

- `server/api/doc-reviews` has the identical `user_id`-missing gap as Bug 1 (it wires
  `run_id` via `withLLMRunID` in `review-document.go:1279` but has no `user_id` equivalent) —
  deliberately **not fixed** in this pass, since the user's report was scoped to
  doc-processing. Worth a follow-up bug/fix using the same pattern.
- `server/api/file-converters/service.go`'s `emitLineFileGeneratedEvent` — the fully
  automated (non-manual) trigger for doc-processing — still has no source for `user_id` at
  all (no authenticated request, no populated `kb.inputs.owner`). It will keep producing
  `user_id = NULL` events, caught only by the generic insert-time alarm in `llmusage/sink.go`,
  not by a generation-time alarm the way `jetstreamhandler.PublishEvent` now has. Explicitly
  deferred; the user's own instruction was "do not worry about backfills," but this is a
  forward-looking gap, not a backfill.
- `kb.inputs.owner` (the column that would make "attribute to the record's owner" a viable
  design instead of "attribute to whoever triggered the run") is NULL for record 416 and
  appears unpopulated workspace-wide — confirmed by direct query, not just for this record.
  No decision was made on whether/how to start populating it; the chosen design
  (generator-supplies-user_id) sidesteps needing it, but it may still be worth fixing
  separately for other reasons (e.g. billing-by-document-owner).
- Existing null rows (everything before this fix, including the full `run_id=143` / record
  416 run) are explicitly **not** being backfilled, per the user's direct instruction.

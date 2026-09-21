# `enrich_metrics` and `merge_resolve_metrics` report `cache_hit=0` while pass 1 reports ~96% — the layout is now correct, but the provider's prefix cache needs ~15–60 s to become reusable and both stages fan out in ~10 ms with no priming

Date: 2026-08-16

Status: root-caused and empirically confirmed against the live DeepSeek endpoint. No fix implemented.

Scope: `extract_metrics` pass 2 (`enrich_metrics`) and the merge-resolve stage
(`merge_resolve_metrics`) in `ChenWeb/server/api/doc-processing/`. The same failure mode applies to
every "fan out N concurrent LLM calls that share a long constant prefix" site — `enrich_scene_blocks`
shows it too (9.4% hit rate on the 2026-07-23 run).

Code read: `extract-metrics.go` (`enrichMetricCandidates` ~3357-3460, `extractMetricPayload` ~2517-2590,
`ProcessChunk` ~3528-3585, `buildMetricRelationBatchPrompt` ~1490-1537), `metrics_merge_resolve.go:16-90`,
`chunk_batch_coordinator.go:265-330`, `chunk_batch.go:58-68`, `chunk_summary_shared.go` (`runConcurrent`),
`input_lines.go` (`canonicalChunkInputText`), `llm_capture_input.go`, `cache_log.go:40-50`,
`shared/go/api/llm/openai_client.go` (`buildMessages` 412-435, `extractTextWithFormat` 210-260),
`shared/go/api/llm/structured_output.go`.

Evidence: `llm_usage_event` on `miner` plus the archived request/response bodies under
`/Users/cding/Apps/llm-logs/2026/2026-08/2026-08-16/account-77566441-.../bodies/`, and a set of
controlled replays against `https://api.deepseek.com` (`max_tokens=1`) described in §4.

Related: ADR `202606/2026062501-adr-deepseek-cache.md`, ADR `202606/2026062701` (doc-processor
extension), `Capsules/coding-capsules/doc-processor/+CAPSULE.md` §6.2,
[[metrics-enrich-cache-documentfirst]], commits `37997b79` (2026-08-15, pass 2 → task-first) and
`0fc20046` (2026-08-16 06:49, pass 2 → canonical chunk, document-first).

---

## 1. Summary

The reported symptom is real and reproducible, but **the prompt layout is no longer the problem.**
As of `0fc20046` (2026-08-16 06:49) an `enrich_metrics` request is **94.8% byte-identical** to its
siblings, and its first ~1050 tokens are byte-identical to the pass-1 request for the same chunk.
Verified directly from the archived bodies.

Three separate things produce the `cache_hit=0` in the quoted log:

- **RC-1 (dominant, ours).** DeepSeek's prompt cache does not make a *newly seen* prefix reusable
  immediately. Measured on this account: a fresh 2 900-token prefix is still unusable at **t+15 s**
  and fully reusable by **t+60 s**. Pass 2 fires all 12 batches inside a **10 ms** window
  (`14:32:29.476` → `14:32:29.486`) with no priming call, so every batch pays full price for the
  ~9 800-character head they all share. Merge-resolve does the same with 6 groups at
  `14:35:18.439`–`.446`.
- **RC-2 (why it was exactly 0 rather than ~1 024).** `0fc20046` shipped that morning; the
  14:32 run was the **first execution ever** of the new enrich prompt shape, so not even the
  chunk-boundary node existed yet. That run created it. Replaying the identical prefix today returns
  **1 024 cached tokens, every time**. The Aug-15 task-first experiment (`37997b79`) was judged the
  same way — measured on its own first run, which always scores ~0.
- **RC-3 (invalidates the baseline being compared against).** Pass 1's ~96% is **not** prefix
  sharing. It is whole-request repetition: pass-1 bodies are byte-identical across re-runs of the
  same document, so on run 2+ DeepSeek serves the entire request. `LLM_CALL_STAGGER=10` (s) —
  the Phase 1b "wait for the prompt prefix to be cached" in `chunk_batch_coordinator.go:294-305` —
  is below the provider's ~15–60 s window, so that seed-and-wait primes nothing *within* a run.

Plus one independent layout defect (**RC-4**) in merge-resolve, and one adjacent cost defect
(**RC-5**), both in §5.

## 2. Observed data — record 416, run 2026-08-16 14:30–14:35

From `llm_usage_event` (provider-reported, authoritative):

| stage | calls | prompt tokens | cache hit | hit % |
|---|---|---|---|---|
| `extract_metric_candidates` (pass 1) | 12 | 19 293 | 18 560 | **96.2%** |
| `enrich_metrics` (pass 2) | 12 | 48 692 | 0 | **0%** |
| `merge_resolve_metrics` | 6 | 9 872 | 0 | **0%** |
| `resolve_ambiguous_object` | 1 | 726 | 0 | 0% |

Confirmed provider-side, not a logging artifact — raw response for `llm-f2ac7d2a`:

```json
"usage": { "prompt_tokens": 3082,
           "prompt_tokens_details": { "cached_tokens": 0 },
           "prompt_cache_hit_tokens": 0, "prompt_cache_miss_tokens": 3082 }
```

Both stages use the same account (`77566441-…`), profile (`4604241e-…`), model
(`deepseek-v4-flash`), `system_fingerprint`, `temperature`, and `response_format`. The only
difference is the message content.

Aggregate since 2026-08-09 (all records):

| call_reason | calls | prompt tokens | hit | hit % |
|---|---|---|---|---|
| `extract_metric_candidates` | 212 | 312 267 | 278 400 | 68.0% |
| `extract_metric_definitions` | 20 | 45 126 | 21 888 | 48.5% |
| `merge_resolve_metrics` | 81 | 174 430 | 22 272 | 12.8% |
| `enrich_metrics` | 187 | 534 585 | 44 160 | **7.7%** |

## 3. The prompt is already 94.8% constant

`llm-f2ac7d2a` (enrich, chunk `d1cffd15`), user message = 10 380 chars:

| segment | chars | varies with |
|---|---|---|
| `<DOCUMENT_INPUT>` = `canonicalChunkInputText(chunk.Lines, docCtx)` | 2 390 | chunk (identical to pass 1's, byte-for-byte) |
| `<TASK>` enrich prompt (`prompt-enrich-metrics-v5.md`) | 6 140 | never |
| `<TASK>` JSON schema (`buildMetricRelationBatchPrompt`) | 1 313 | never |
| `<TASK>` `Candidates: [...]` | ~537 | **per batch** |

So only ~5% of each request is unique, and the varying part is already last — the layout the ADR
asks for. `buildMetricRelationBatchPrompt` no longer duplicates the chunk as "Source lines"
(removed in `0fc20046`), which is correct: the chunk is already the document.

Byte-level check of a pass-1/pass-2 pair for the same chunk (`llm-43191240` vs `llm-f2ac7d2a`):
identical system message, identical non-message body fields, and a **2 475-character common prefix**
(≈1 050 tokens) covering the whole document plus the opening of `<TASK>`.

## 4. Controlled replays against the live endpoint

Archived bodies replayed verbatim with `max_tokens=1`:

| probe | prompt | hit | note |
|---|---|---|---|
| A — pass-1 body verbatim | 1 707 | 1 664 | entry exists, as at 14:31 |
| B — pass-2 body verbatim | 3 082 | 3 072 | proves the captured body **is** what was sent at 14:32 (that call created this entry) |
| C — the 2 475-char shared prefix + novel tail | 1 074 | **1 024** | partial-prefix matching works |
| D — same, different chunk, prefix never probed before | 1 348 | **1 280** | works cold, no warm-up needed |
| G0–G7 — 8 such probes fired concurrently | 957–1 944 | 896–1 920 | works under concurrency |
| H — real enrich body, only `Candidates:` changed (9 824 identical chars) | 2 934 | 1 024 | stops at the chunk node; the deeper node does not exist yet |

**The latency measurement (the decisive one).** Novel 9 800-char head (~2 900 tokens), one seed call
then re-probes with a different tail:

| when | prompt | hit |
|---|---|---|
| seed, t=0 | 2 948 | 1 024 |
| t+15 s | 2 948 | 1 024 |
| t+60 s | 2 948 | **2 816** |
| t+180 s | 2 948 | 2 816 |
| t+420 s | 2 948 | 2 816 |

And the fan-out shape, on a novel prefix:

| pattern | result |
|---|---|
| 6 calls fired concurrently, no seed | all 6 → 1 024 hit (only the pre-existing chunk node) |
| seed, wait 5 s, then 5 concurrent | all 5 → 1 024 hit — **5 s is not enough** |

That is the whole mechanism: the reusable node appears somewhere between **t+15 s and t+60 s** after
the seeding request. Anything fanned out inside that window pays in full. Steady-state ceiling for
the current enrich layout is **~2 816 / 2 948 ≈ 95%**.

## 5. Two further defects found while investigating

**RC-4 — `merge_resolve_metrics` sends its prompt template twice and splits its own prefix.**
`metrics_merge_resolve.go:70-72`:

```go
taskPrompt := mergeResolveTask(p.MergeResolvePromptText, recordID, candidates)
in := newLLMJSONInput(ctx, p.MergeResolvePromptRef, p.MergeResolvePromptText, modelName, taskPrompt, ...)
//                                                  ^^ PromptText              ^^ InputText
```

`newLLMJSONInput(ctx, promptName, promptText, modelName, inputText, …)` — so `InputText` is the
template *with the record id and candidates injected into its middle*, and `PromptText` is the bare
template. Document-first then renders
`<DOCUMENT_INPUT>{template+candidates}</DOCUMENT_INPUT><TASK>{template}</TASK>`. Confirmed in
`llm-f5993ea8`: document = 3 563 chars, task = 2 928 chars, and the two are the same text.
Consequences: ~2 900 chars re-sent per call for nothing, and because the candidates sit *mid-template*
the shared constant prefix is truncated at **1 584 chars → 384 tokens**, which is exactly the
384/448/640 partial hits seen in `llm_usage_event` for this call_reason.

**RC-5 — thinking is never actually disabled.** *(FIXED 2026-09-22: `extractTextWithFormat`
now sends the `thinking` field for any non-empty `ThinkingType`, not only `"enabled"`.
`{"thinking":{"type":"disabled"}}` was verified accepted by `api.deepseek.com` for both
`deepseek-flash` and `deepseek-v4-pro`; both think by default. Note that disabling it is
not universally desirable — on `extract_products` Pass 1 it costs ~20% of distinct
mentions; see "Thinking Must Stay On For Pass 1" in `extract-products-spec.md`.)* `forceDisableThinking` (`extract-metrics.go:906-917`)
sets `ThinkingType = "disabled"`, and `applyStructureModelConfigToExtractor`
(`doc-structure-analyzer.go:536`) copies it to the client — but `extractTextWithFormat`
(`openai_client.go:246-248`) only ever *adds* a `thinking` field when the value is `"enabled"`, and
never sends `{"type":"disabled"}`. `deepseek-flash-chen` in `.models.toml` has `thinking_type = ""`.
Net effect: the provider default (thinking on) applies. Measured on `llm-43191240`:
`completion_tokens 3062`, of which `reasoning_tokens 2929` — 96% of the output tokens on a call that
is supposed to run with thinking off. This is a pure cost/latency loss and independent of caching.

**Minor.** `cacheTokenCounts(p.Extractor)` (`cache_log.go:40-50`) reads the client's process-wide
`LastJSONUsage()`. It is mutex-guarded so there is no data race, but under concurrent fan-out the
value logged next to a batch may belong to a different in-flight call. The `cache_hit`/`cache_miss`
fields in the app log are therefore indicative only — `llm_usage_event` is the source of truth. (In
this run they happened to agree.)

## 6. Recommended remediation

1. **Stop measuring cache effectiveness on the first run after a prompt change.** Any layout scores
   ~0 on its first execution. Re-run record 416 with the current binary and read `llm_usage_event`,
   not the first run's log. Expect ~1 024 hit/call immediately, rising as the deeper nodes form.
2. **Prime before fan-out in pass 2 and merge-resolve**, mirroring `chunk_batch_coordinator.go`'s
   Phase 1a/1b: issue batch 0 alone, then release the rest. This is only worth doing if the wait is
   raised to the measured window — which costs 45–60 s of wall time per stage. Given that the head
   is constant *across runs*, the cheaper variant is to accept the first run's miss and let the node
   persist: no seed, no wait, and runs 2+ get ~95% for free.
3. **`LLM_CALL_STAGGER=10` is mis-tuned** (`mise.local.toml:177`). It is documented as "wait for the
   prompt prefix to be cached" but is 4–6× below the measured build time, so it buys latency without
   buying cache. Either raise it to ~60 or drop the pretence and set it low.
4. **Fix RC-4**: pass `mergeResolveTask(...)` output as the prompt and put only the per-group
   candidate JSON in `InputText` — or, better, restructure `mergeResolveTask` so the record id and
   candidates go at the *end* of the template rather than the middle. Either change raises the
   shared prefix from 384 tokens to ~1 400 and removes ~2 900 duplicated chars per call.
5. **Fix RC-5**: send `{"thinking": {"type": "disabled"}}` when the resolved thinking type is
   `"disabled"`, and set `thinking_type = "disabled"` on `deepseek-flash-chen` in `.models.toml`.
6. **Consider a cross-chunk constant prefix for pass 2.** Today the chunk (chunk-specific, 2 390
   chars) precedes the 7 453 chars of constant prompt+schema, so no two chunks share anything.
   Putting the constant prompt+schema first would give *every* enrich call in the system a shared
   ~1 900-token node at the cost of the ~1 050-token chunk node shared with pass 1. Worth measuring —
   but measure it on the **second** run.

## 7. What was ruled out

- Different model, account, profile, base URL, `temperature`, `response_format`, or
  `system_fingerprint` between the two passes — all identical.
- `docCtx` / chunk-serialization drift between pass 1 and pass 2 — the `<DOCUMENT_INPUT>` blocks hash
  identically (`e766ab9e`, `7867d876`, `3350ee50`, `a9ed244d`, `294c7a28`, `d1cffd15`, `f74258e3`,
  `3bcb32b8`, `ba475d81`, `83244fa0` all appear in both passes' bodies).
- `chunksBySeq` lookup picking the wrong chunk — the hashes match pairwise.
- Structured-output retry text contaminating `InputText` (`buildStructuredRetryInput`) — no retries
  occurred; one usage event per batch.
- Cache eviction between 14:31 and 14:32 — the pass-1 entries were served at 14:31:06 and the same
  prefixes still hit today.
- Concurrency itself suppressing hits — 8 concurrent novel-tail probes all hit (probe G).

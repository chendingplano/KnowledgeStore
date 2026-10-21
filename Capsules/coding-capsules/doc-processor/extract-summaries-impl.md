# Extract summaries implementation

The behavior contract is [extract-summaries-spec.md](extract-summaries-spec.md).
The configurable processor is implemented in ChenWeb and registered in the
production runtime and command helper. Its dependencies are provisioned locally;
normal service startup applies the goose migration. No running service was
restarted and no document-processing request was published by this work.

## Components

- `server/api/doc-processing/extract-summaries-processor.go`: chunk loading,
  complete response validation, source freshness checks, status and logs. Uses
  the normal non-batched Phase B path, so local extraction does not seed or wait
  for the LLM chunk-cache batching coordinator.
- `sumy_runner.go` and embedded `sumy_worker.py`: one cancellable Python process
  per document, Sumy ranking per chunk, exact occurrence-aware source mapping.
- `extract_summary_store.go`: input-row lock, freshness callback, transactional
  replacement scoped to one record/algorithm, and exact selected evidence.
- `project_migrations/20261021000002_create_kb_ex_summaries.sql`: current summary
  column layout plus algorithm/evidence/configuration, unique identities,
  search-column trigger, timestamps and input-deletion cascade.
- `python/sumy/pyproject.toml`, `uv.lock` and `README.md`: pinned direct dependencies,
  resolved dependency lock and deployment setup; the interpreter and NLTK data
  are not embedded in the Go binary.

The local active `config.local.toml` available processor list now includes
`extract_summaries`; existing nonempty automatic defaults remain unchanged.
Other hosts must add it to their active configuration and provision Python.

## Validation

- 10 actual Python worker tests cover English, Chinese, all five algorithms,
  repeated sentences, split sentences, uppercase/short text, empty/image chunks,
  invalid settings, language detection, stop-word-only LSA fallback and a Chinese
  tail without punctuation.
- Go tests cover configuration, complete and grounded worker output, algorithm and
  language matching, missing/duplicate chunks, changed source/buffer, damaged chunk
  references, failure, user stop, SQL rollback and algorithm-scoped replacement.
- The optional real-worker integration test invokes the embedded script through
  the provisioned interpreter for English and Chinese and checks cancellation.
- The optional PostgreSQL integration test passed migration up/down/up and
  repeated up, unique algorithm/chunk identities, the actual installed summary
  search trigger, and cascading deletion in an isolated temporary schema.
  It does not modify the live `kb` table or migration-version history.
- The doc-processor binary builds and `go vet` passes for the processor package
  and command. The frozen benchmark validates with the original digest and all
  its 26 tests pass; no gold annotations or scores were changed.
- The broader processor suite has two unrelated failures:
  `TestLoadSceneBlocksPromptFromEnvDefaultsToEnrichmentPrompt` expects enrichment
  prompt v1 while the generated default is v2; `TestKBMetricsReadersExcludeResolvedRows`
  flags `api/categorytree/source.go` lacking a `ref_mention_id` predicate.
  These files belong to existing work and were left unchanged by this feature.

The independent agent reviewer found two edge cases, both corrected with failing
regressions first: LSA can return no ranked sentences for valid stop-word-only
text, and the legacy chunk loader tolerates absent source references. The worker
now records a deterministic source-order fallback when ranking has no usable
vocabulary/result; this processor strictly validates every artifact reference.
The reviewer rechecked the fixes and found no remaining blocking issues.

## Operational limits

English and Chinese are supported. This produces source-language level-0 extracts,
without generated translation, keywords, categories, embeddings, parent summaries
or global hybrid-search registration. A sentence count is not a character budget;
functional correctness does not establish quality on the frozen benchmark.

Source and chunk files are fingerprinted and checked immediately before database
replacement, under the input row lock. PostgreSQL does not lock external files:
serialize concurrent reprocessing of the same document operationally. Only the
currently selected algorithm is replaced; other algorithm outputs can represent
an earlier chunk generation until separately rerun, with input digests retained
for audit. Historical algorithm outputs are not automatically declared current.

## Completion checklist

- [x] Add failing Python tests for Sumy ranking and exact occurrence-aware source mapping.
- [x] Add the embedded JSON worker and locked Python dependencies; provision tokenizer data.
- [x] Add failing Go tests for chunk handling, isolation, rollback, stop and configuration.
- [x] Add a project goose migration and atomic store for `kb.ex_summaries`.
- [x] Implement the Go processor using the existing chunk buffer/artifact and status/log contracts.
- [x] Register in production runtime and command helper; expose through configured processors.
- [x] Verify actual worker execution, Go tests/build, migration lifecycle and benchmark integrity.
- [x] Update capsule/schema/devdoc, independently review, and commit each repository through jj.

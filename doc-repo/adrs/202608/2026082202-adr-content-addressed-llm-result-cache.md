# ADR 2026082202 — Content-Addressed LLM Result Cache for Document Processors

**Date:** 2026-08-22 \
**Status:** Proposed \
**Component:** ChenWeb — `kb.llm_task_cache`, `kb.llm_task_cache_refs`, `server/api/doc-processing`, `extract_metrics`, `kb.doc_proc_logs` \
**Authors:** Chen Ding (with Codex) \
**Tags:** LLM, cache, document processing, extract_metrics, cost, latency, content addressing

## 1. Change Logs

* 2026/08/22, ADR created from the DZone cache-augmented-agent pattern and the
  SemOS research note `2026082201-rsch-llm-prompt-cache.md`.

## 2. Context

### 2.1 The proposed cache is a result cache, not the existing provider prompt cache

ADR `2026062501-adr-deepseek-cache.md` and the current document-processing code already
optimize DeepSeek's provider-side prompt cache. Chunk-based calls use
`canonicalChunkInputText(...)` as a stable document-first prefix, related calls are
scheduled close together, and provider-reported `prompt_cache_hit_tokens` /
`prompt_cache_miss_tokens` are recorded. That optimization reduces the price of a call,
but it still sends a request to the provider and still runs the model.

The article *Stop Paying Your AI Agent to Do the Same Job Twice* proposes a different
layer in front of the agent:

1. normalize a structured request and check an exact SHA-256 signature;
2. look for a semantically related prior task when exact lookup misses;
3. invoke the agent only for the missing scope, then cache the result.

The important inversion is that ordinary code decides whether an LLM call is needed
before the LLM is invoked. This ADR adopts that inversion for SemOS document processors.
It does not replace provider prompt caching; an actual miss still benefits from the
existing prompt-prefix layout.

### 2.2 `extract_metrics` is the first target

The live `extract_metrics` path has two LLM stages around deterministic orchestration:

```text
per chunk: extract candidate mentions (Pass 1 LLM)
    ↓
deterministically normalize/collect candidates
    ↓
per chunk candidate batch: enrich candidates (Pass 2 LLM)
    ↓
deterministically normalize/deduplicate final metric rows
```

The same document is often processed again. Unless chunking is deliberately changed,
the persisted chunk content is stable. Even after rechunking, an unchanged canonical
chunk can still be recognized from its content. The Pass 1 request is therefore a
natural exact-cache unit. Pass 2 is also cacheable when the canonical chunk and the
canonical candidate batch are identical.

The deterministic transformations between and after these calls are cheap. Persisting
their outputs in a separate cache would add complexity without avoiding meaningful
cost, so they will be rerun in memory on every processor run.

### 2.3 A vector near-match is not proof that extraction output is reusable

The article uses pgvector to retrieve a similar prior task. As the research note points
out, similarity solves only candidate discovery:

```text
A. find a similar prior task
B. prove which prior scope is covered and compute the missing scope
```

For metric extraction, an embedding score cannot prove that two chunks contain the same
requirements, numeric values, units, negation, or applicability conditions. Serving a
semantically similar result as a full hit could silently lose or alter compliance facts.
The article itself recommends favoring correctness over cache hit rate for financial or
compliance work.

SemOS already has a stronger domain boundary than semantic similarity: the current
processor decomposes work into chunks and deterministic candidate batches. Exact
content identity at those boundaries can prove coverage. Therefore this ADR implements
partial matching as set difference over exact stage units, not as a vector threshold.

### 2.4 Existing force flags cannot be overloaded

Document-processing events already use:

- `force`: whether a processor runs when prior persisted artifacts exist;
- `force_clear`: whether a running processor wipes or merges prior artifacts.

Neither flag says whether successful LLM results may be reused. Reusing the article's
`--force` name for cache bypass would create ambiguous and breaking behavior. Cache
control needs its own field.

### 2.5 Repeated LLM runs are sometimes intentional

ADR `2026071002-adr-doc-processor-incremental.md` records that repeated metric
extraction can produce different candidates because model execution is
non-deterministic. A cache intentionally freezes one successful answer for one exact
request. That is desirable for routine reprocessing, cost, latency, and reproducibility,
but it conflicts with an explicit experiment that reruns the model to seek additional
recall. The operator must be able to refresh or disable this result cache without
changing artifact merge behavior.

## 3. Decision

### DR1 — Add a ChenWeb-owned, persistent `kb.llm_task_cache`

Add a project-specific PostgreSQL table. Do not put the implementation in `shared/go`
until a second application has the same result-cache contract; the first use is tightly
coupled to SemOS document stages, knowledge-store isolation, and document-processing
telemetry.

```sql
CREATE TABLE kb.llm_task_cache (
    id                    BIGSERIAL PRIMARY KEY,
    ks_store_id           BIGINT NOT NULL
                          REFERENCES kb.knowledge_store(id) ON DELETE CASCADE,
    task_type             TEXT NOT NULL,
    task_stage            TEXT NOT NULL,
    key_version           INT NOT NULL DEFAULT 1,
    signature_hash        VARCHAR(64) NOT NULL,
    generation            INT NOT NULL DEFAULT 1,

    request_fingerprint   JSONB NOT NULL,

    prompt_ref            TEXT NOT NULL,
    prompt_hash           VARCHAR(64) NOT NULL,
    model_ref             TEXT NOT NULL,
    model_fingerprint     VARCHAR(64) NOT NULL,
    contract_hash         VARCHAR(64) NOT NULL,

    result                JSONB NOT NULL,
    result_hash           VARCHAR(64) NOT NULL,
    status                TEXT NOT NULL DEFAULT 'complete'
                          CHECK (status IN ('complete', 'invalidated')),
    expires_at            TIMESTAMPTZ,
    invalidated_at        TIMESTAMPTZ,
    invalidation_reason   TEXT,

    ref_count             BIGINT NOT NULL DEFAULT 0 CHECK (ref_count >= 0),
    hit_count             BIGINT NOT NULL DEFAULT 0,
    last_hit_at           TIMESTAMPTZ,
    create_time           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    modify_time           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (ks_store_id, task_type, task_stage, key_version, signature_hash, generation),
    UNIQUE (id, ks_store_id)
);

CREATE UNIQUE INDEX uq_kb_llm_task_cache_active
    ON kb.llm_task_cache
       (ks_store_id, task_type, task_stage, key_version, signature_hash)
    WHERE status = 'complete';

CREATE TABLE kb.llm_task_cache_refs (
    cache_entry_id        BIGINT NOT NULL,
    input_record_id       BIGINT NOT NULL,
    ks_store_id           BIGINT NOT NULL,
    first_used_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (cache_entry_id, input_record_id),
    FOREIGN KEY (cache_entry_id, ks_store_id)
        REFERENCES kb.llm_task_cache(id, ks_store_id) ON DELETE CASCADE,
    FOREIGN KEY (input_record_id, ks_store_id)
        REFERENCES kb.inputs(id, ks_store_id) ON DELETE CASCADE
);

CREATE INDEX idx_kb_llm_task_cache_refs_input
    ON kb.llm_task_cache_refs (input_record_id, cache_entry_id);
```

`ks_store_id` is the phase-1 security and policy namespace and is part of both the
unique lookup index and the signature input. The cache service has no lookup method
without a required `ks_store_id`; every lookup SQL statement includes
`WHERE ks_store_id = $1`. Cache entries must never be reused across knowledge stores,
even if document bytes happen to match. The foreign key also ensures that deleting a
knowledge store deletes its cache.

`kb.llm_task_cache_refs` records every input record that created or consumed an entry.
The migration adds `UNIQUE (id, ks_store_id)` to `kb.inputs`; the two composite foreign
keys then make cross-store references impossible and prevent either parent from moving
to another store while references exist. Inputs with no valid positive `ks_store_id`
are not cache-eligible and continue through the live path.

Reference-count triggers serialize on the parent cache row. A newly inserted reference
atomically increments `ref_count`; deleting one atomically decrements it and deletes the
parent when the returned count is zero. `ON CONFLICT` updates only `last_used_at` and do
not increment. PostgreSQL row-update locking makes concurrent final-reference deletes
resolve from 2→1→0 rather than both observing a stale count. A concurrent attachment
either increments before the decrement/delete or finds that the parent was deleted and
fails open to the live path. This applies equally to explicit reference removal and
`kb.inputs` cascade deletion. Therefore document deletion cannot leave an unreferenced
result behind, while a result still justified by an identical document in the same
knowledge store may remain.

`generation` resolves refresh and audit history. At most one generation for a logical
key has `status='complete'` (enforced by `uq_kb_llm_task_cache_active`). Refresh runs in
one transaction: mark the prior generation `invalidated`, then insert generation N+1.
The prior result remains available for audit until retention removes it, but it is never
eligible for lookup.

Every publish transaction takes a transaction-scoped PostgreSQL advisory lock derived
from `(ks_store_id, task_type, task_stage, key_version, signature_hash)`, then calculates
`generation = COALESCE(MAX(generation), 0) + 1`. A cold fill first rechecks for an active
generation under that lock: if one exists, it is the first-valid-writer winner and the
current record attaches to it; otherwise the new next generation is inserted. Historical
invalidated rows can therefore never make a cold fill look like a competing active win.
The advisory lock is held only for this short database publication transaction, never
while calling the provider.

Only validated, successful, complete LLM outputs are stored. Transport errors, parse
failures, partial JSON, cancelled calls, and stopped processor runs are never cached.

### DR2 — Build signatures from the complete behavior-affecting request

The signature is not merely a hash of `(task_type, params)`. For an LLM call, prompt,
model configuration, structured-output contract, and application normalization behavior
are all inputs to the result.

The application builds a versioned canonical JSON object and hashes its UTF-8 bytes
with SHA-256:

```json
{
  "key_version": 1,
  "ks_store_id": 17,
  "task_type": "extract_metrics",
  "task_stage": "candidate_extraction",
  "input_hash": "sha256(canonicalChunkInputText)",
  "stage_params_hash": "sha256(canonical stage parameters)",
  "prompt_hash": "sha256(prompt file contents plus generated task suffix)",
  "model_fingerprint": "sha256(provider/model/revision/effective options)",
  "contract_hash": "sha256(structured-output schema and normalizer revision)"
}
```

Canonicalization rules are fixed for `key_version = 1`:

- descriptors are serialized with RFC 8785 JSON Canonicalization Scheme (JCS), including
  its object-key, string, and number rules, before SHA-256;
- arrays retain order unless a stage contract explicitly defines and canonicalizes them
  as sets;
- strings are preserved exactly after the same stage-specific trimming already used by
  the processor; no case folding or Unicode rewriting is introduced unless that stage's
  existing semantics already do so;
- timestamps, run IDs, event IDs, log locations, retry counters, and the current
  `input_record_id` are excluded;
- the effective model fingerprint includes provider, concrete model identifier,
  configured model revision/cache revision, temperature, reasoning mode, response
  format, and every other option that can affect output;
- prompt hashes use file contents, not only prompt filenames;
- contract hashes cover both the structured-output schema and the application code's
  normalization contract. A deliberate behavior change bumps the stage's cache
  revision or `key_version`.

The stored `request_fingerprint` contains hashes and non-sensitive diagnostic metadata,
not the full prompt or canonical chunk text. `result` necessarily contains extracted
document data and therefore inherits the same access, backup, retention, and deletion
requirements as other `kb` document artifacts. The cache table is not exposed through
a user-facing API. Administrative reads and invalidations use the same knowledge-store
authorization check as the source inputs; direct application SQL never queries a key
without `ks_store_id`.

### DR3 — Implement the article's tiers as exact unit reuse, deterministic coverage planning, then LLM fallback

For `extract_metrics`, the lookup flow is:

```text
Current document manifest
    ↓
Tier 1: exact cache lookup for each stage unit
    ├─ hit  → validate cached result → use it
    └─ miss → add unit to missing_scope
                    ↓
Tier 2: deterministic scope comparison
    covered_scope = exact-hit chunk/batch units
    missing_scope = current units minus exact-hit units
                    ↓
Tier 3: invoke the LLM only for missing_scope
    ↓
validate output → publish cache entry → combine in current unit order
```

This retains the article's essential property—work is proportional to the missing
scope—without trusting semantic proximity as equivalence.

The initial stage units are:

1. **`candidate_extraction` (Pass 1):** one canonical chunk. On a hit, load the cached
   validated stage result, then run current annotation and normalization code so run-local
   chunk indexes, logging IDs, and in-memory types are regenerated rather than cached.
2. **`candidate_enrichment` (Pass 2):** one deterministic candidate batch plus its
   canonical source chunk. The stage-parameter hash covers the ordered canonical
   candidate JSON and all grouping-relevant settings. `METRIC_ENRICH_GROUP_SIZE` does
   not need a separate special case because changed batch membership changes the
   canonical candidate payload, but it is retained in diagnostic metadata.

After Pass 1 hits and misses are assembled in current chunk order,
`mentionsAsCandidates(...)` runs normally. Pass 2 batches are then constructed from
that current candidate list and independently looked up. `dedupeFinalMetricRows(...)`,
identity resolution, incremental merge, persistence, indexing, and artifact-file refresh
all run normally; cached LLM output does not bypass downstream business logic.

The cache boundary is the named Go value `ValidatedStageResultV1`: the parsed and
structured-output-validated stage envelope returned by the extractor, before
`annotateMetricCandidatePayload`, run-local IDs, processor normalization, or persistence.
Both live and cached paths must produce this same type before entering downstream code.

There is no persisted cache for candidate deduplication or final-row deduplication.
Those are deterministic, inexpensive functions and may change independently without
requiring an LLM call.

### DR4 — Do not enable vector semantic hits for authoritative extraction

`kb.llm_task_cache` has no embedding column in this ADR. A semantically similar chunk
or candidate batch is never served as either a full or partial extraction hit.

Semantic retrieval may be proposed later for a task type only if that task defines and
tests a domain-specific scope comparator with all of the following properties:

- it can prove what prior scope is covered;
- it can calculate the exact missing scope;
- it can merge old and new results without losing provenance or changing meaning;
- a near match cannot be promoted directly to a full hit from similarity score alone;
- production evaluation demonstrates an acceptable false-reuse rate for the task's
  risk class.

Until then, semantic retrieval is an alternative considered and rejected, not an
incomplete part of this decision.

### DR5 — Cache freshness is dependency-based; time expiry is optional policy

For metric extraction, elapsed time does not make an unchanged chunk, prompt, contract,
and immutable model revision incorrect. Their hashes are the freshness test. The
default `expires_at` is therefore `NULL`.

Entries miss naturally when source input, document context, prompt content, model
fingerprint, output contract, or cache-key revision changes. Operators may also
invalidate entries explicitly. A task type whose answer depends on live external state
must set `expires_at` according to its own policy and is out of scope for the initial
`extract_metrics` rollout.

Model aliases are not assumed immutable. Every cache-enabled model profile must expose
an explicit `cache_revision` (or a provider-supplied immutable revision) that participates
in `model_fingerprint`. When a provider changes behavior behind an alias, or when the
team wants new outputs, incrementing `cache_revision` causes a clean miss without
deleting history.

### DR6 — Add an independent `llm_cache_mode`

Add `llm_cache_mode` to document-processing run parameters. It is independent of
`force` and `force_clear`:

| Mode | Read cache | Invoke on miss | Write successful result | Intended use |
| --- | --- | --- | --- | --- |
| `use` | yes | yes | yes | normal operation |
| `refresh` | no | yes | yes, publish a new generation | intentional fresh model run |
| `off` | no | yes | no | diagnosis, benchmarks, emergency bypass |
| `write` | compare only; never serve | always | insert only when absent | deployment-only shadow validation |

If omitted, the mode comes from `DOC_PROCESS_LLM_CACHE_MODE`. The rollout default is
`off`; after shadow validation it becomes `use`. Per-event input accepts only `use`,
`refresh`, and `off`; `write` is accepted only from deployment configuration. Invalid
values reject the event rather than silently selecting a mode.

Existing flags retain their meanings. Examples:

- `force=true, force_clear=false, llm_cache_mode=use`: rerun the processor, reuse exact
  LLM stage results, and merge artifacts;
- `force=true, force_clear=false, llm_cache_mode=refresh`: rerun every LLM stage and
  merge the newly sampled artifacts, preserving the iterative-recall workflow;
- `force=true, force_clear=true, llm_cache_mode=use`: rebuild persisted artifacts from
  cached stage outputs where valid;
- `llm_cache_mode=off`: neither reads nor writes result cache, regardless of other flags.

On `refresh`, replacement occurs only after a new result passes the same schema and
normalization validation as a live result. A failed refresh leaves the last valid cache
entry intact. If `force=false` causes the processor to skip before stage execution,
`llm_cache_mode` has no effect. `force_clear` never invalidates result-cache entries; it
controls persisted artifacts, not the validity of an LLM stage result.

Model routing by cache mode is explicit:

```text
use:     primary cache → live primary → fallback cache → live fallback
refresh: live primary → live fallback; publish a new generation for the model used
write:   live primary → live fallback; compare/seed that model's shadow baseline only
off:     live primary → live fallback; no cache read or write
```

Thus `refresh` and `write` never serve a fallback cache entry. A cached fallback is
consulted only in `use`, and only after the live primary attempt fails.

### DR7 — Cache failures fail open; cached data fails closed

The result cache is an optimization, not a new availability dependency:

- database lookup or cache-write failure is logged and the live LLM path proceeds;
- malformed cached JSON, a result-hash mismatch, an unsupported key version, or a
  contract-invalid payload is soft-invalidated with a reason, treated as a miss, and
  emits one warning for that generation; an expired entry is invalidated and then
  treated as a normal miss, while an already-invalidated entry is ineligible;
- cached payloads pass the same output-contract validation as provider responses before
  entering processor logic;
- no cached result is served after cancellation or a processor stop request is observed;
- failure to write a result after a successful LLM call does not fail document
  processing.

An expired active generation is atomically changed to `invalidated` with reason
`expired` before lookup returns a miss; this releases the partial unique index so a new
generation can be published. A failed quarantine/invalidation still falls through to
the live call, but publishing is skipped until the conflicting row can be repaired.

Concurrent workers may cold-miss the same key and both call the model. Each process uses
singleflight/coalescing for identical in-process keys; cross-process duplicate cold
fills are accepted in phase 1. Cold fill is **first-valid-writer wins**:
the advisory-locked publication transaction in DR1 rechecks active state, followed by
attaching the current record reference to the winning entry. This is storage-idempotent
even though the two sampled LLM results may differ.

A refresh records the expected active entry ID/generation (or `none`) before its live
call. After validation it acquires the same logical-key advisory lock and performs a
compare-and-swap: publish only if the active generation still equals the expected value.
If another cold fill or refresh changed active state during the remote call, the refresh
logs `refresh_conflict`, returns its valid live result to the current processor run, and
does not alter the winner. If the comparison succeeds, it invalidates the expected row
(if any) and inserts `MAX(generation)+1` atomically.

Holding a database lock or lease across a remote LLM call is rejected for the first
version because it adds failure recovery and connection-lifetime risk to an optimization.

### DR8 — Reuse existing telemetry and distinguish result-cache outcomes from provider-cache tokens

Every stage lookup writes a structured `kb.doc_proc_logs` record with
`activity_name = 'llm_result_cache'`. `extra_info` includes:

```json
{
  "cache_entry_id": 912,
  "ks_store_id": 17,
  "task_stage": "candidate_extraction",
  "signature_hash": "...",
  "outcome": "hit|miss|expired|invalid|bypass|write|write_failed|refresh_conflict|shadow_same|shadow_different",
  "llm_cache_mode": "use",
  "chunk_seq": 4,
  "batch_index": null
}
```

Cache hits do not create fake `llm_usage_event` rows because no provider call occurred.
Actual misses continue through existing LLM telemetry and retain provider-side
`prompt_cache_hit_tokens` / `prompt_cache_miss_tokens`. Reports must label these as two
different mechanisms:

- **result-cache hit:** entire LLM call avoided;
- **provider prompt-cache hit tokens:** an LLM call occurred, but the provider reused a
  prompt prefix.

The cache row's `hit_count` and `last_hit_at` are updated best-effort. Operational
reports should derive request-level hit rate, avoided calls, latency, and estimated
avoided cost from `kb.doc_proc_logs` joined to actual `llm_usage_event` data, not from
provider token counters alone.

### DR9 — Roll out in write-only shadow mode before serving hits

Rollout order:

1. migrate the table and deploy key construction, validation, writes, and telemetry;
2. run with `DOC_PROCESS_LLM_CACHE_MODE=write` (deployment-only shadow mode: never
   serve hits; insert a baseline only when no entry exists, otherwise execute live and
   compare the fresh `ValidatedStageResultV1` hash with the unchanged baseline);
3. compare baseline/fresh `ValidatedStageResultV1` hashes and downstream benchmark
   outputs on representative documents, including
   Chinese/English, tables, overlap lines, prompt changes, fallback models, changed
   chunking, cancellation, and manual reruns;
4. enable `use` for `candidate_extraction` only;
5. validate cost, latency, hit rate, and extraction-quality metrics;
6. enable `candidate_enrichment` only after Pass 1 is stable.

`write` is an operational rollout mode, not accepted in per-event user input. It always
executes live. It never invalidates or replaces an existing baseline, so repeated shadow
comparisons remain anchored to the result that `use` would have served. Creating or
comparing a shadow baseline also records the current input in
`kb.llm_task_cache_refs`, because that input is provenance for the stored result.

Shadow comparison uses exactly the stored `result_hash` algorithm: JCS canonicalization
of the complete `ValidatedStageResultV1` envelope followed by SHA-256, on both baseline
and fresh values. Telemetry records `shadow_same` or `shadow_different` plus both hashes;
it never drops fields or applies a second normalizer. Two simultaneous first-baseline
writers use DR1's first-valid-writer publication rule; the loser compares its fresh hash
to the committed winner and logs the resulting outcome.

No backfill job is required. Cache entries are populated by normal processing, and an
empty cache preserves current behavior.

## 4. Alternatives Considered

### A1 — Rely only on DeepSeek prompt caching

Rejected. It reduces input-token cost but still performs a network request and model
execution. It cannot produce a zero-call exact hit or reuse only unchanged chunks across
a reprocessed document.

### A2 — Implement the article's pgvector similarity tier immediately

Rejected for authoritative extraction under DR4. Similarity can retrieve a plausible
prior chunk but cannot prove that numeric, normative, or applicability details are
equivalent. Deterministic chunk/batch scope comparison gives safe partial reuse now.

### A3 — Cache only the final `kb.metrics` rows for an input record

Rejected. It ties reuse to `input_record_id`, prevents cross-record reuse within a
knowledge store, bypasses current merge/identity/indexing logic, and turns any downstream
logic change into a difficult cache invalidation problem. Caching at LLM call boundaries
avoids the expensive work while rerunning current deterministic code.

### A4 — Cache deterministic deduplication outputs

Rejected. The saved compute is negligible compared with an LLM call, while another
persisted intermediate adds invalidation and migration surface.

### A5 — Put a generic cache in `shared/go`

Deferred. One project-specific implementation is not evidence of a stable shared API.
Extract a shared package only after another application needs compatible key, security,
storage, and telemetry semantics.

### A6 — Treat existing `force=true` as cache bypass

Rejected. It would change an established processor-control contract and would prevent
operators from rerunning persistence/merge logic while still benefiting from cached LLM
stages.

## 5. Database Migration

Add one goose migration in `ChenWeb/project_migrations/` to create
`kb.llm_task_cache`, `kb.llm_task_cache_refs`, their indexes, the reference-count
triggers, and the `UNIQUE (id, ks_store_id)` constraint required on `kb.inputs` by the
composite reference foreign key. Add invalidated-entry cleanup to the existing scheduled
LLM-telemetry retention job. The down migration drops only these new triggers, functions,
tables, indexes, and composite uniqueness constraint. Startup migration execution remains
in the existing ChenWeb migration path; no ad hoc `CREATE TABLE` is added to request
handling.

No existing data is rewritten. No pgvector extension or vector index is added by this
ADR.

## 6. Data Formats

### 6.1 Stage request descriptor

```json
{
  "key_version": 1,
  "ks_store_id": 17,
  "task_type": "extract_metrics",
  "task_stage": "candidate_enrichment",
  "input_hash": "64 lowercase hex characters",
  "stage_params_hash": "64 lowercase hex characters",
  "prompt_hash": "64 lowercase hex characters",
  "model_fingerprint": "64 lowercase hex characters",
  "contract_hash": "64 lowercase hex characters"
}
```

### 6.2 Covered and missing scope (runtime only)

`covered_scope` and `missing_scope` are planner values, not persisted claims inferred
from embeddings:

```json
{
  "task_type": "extract_metrics",
  "task_stage": "candidate_extraction",
  "covered_scope": [
    {"chunk_seq": 1, "signature_hash": "..."},
    {"chunk_seq": 2, "signature_hash": "..."}
  ],
  "missing_scope": [
    {"chunk_seq": 3, "signature_hash": "..."}
  ]
}
```

The current processor executes only `missing_scope`, then reassembles results in current
chunk/batch order. Scope is never inferred solely from a cosine score.

### 6.3 Cached result envelope

```json
{
  "result_version": 1,
  "task_stage": "candidate_extraction",
  "payload": {
    "language": "zh",
    "candidates": []
  }
}
```

The `payload` is the validated stage output before run-local IDs and persistence-specific
decorations. `result_hash` is SHA-256 over canonical JSON for the whole envelope.

## 7. Environment Variables

| Variable | Values / default | Purpose |
| --- | --- | --- |
| `DOC_PROCESS_LLM_CACHE_MODE` | `off` initially; later `use`; deployment may use `write` | Global rollout and emergency control |
| `DOC_PROCESS_LLM_CACHE_INVALIDATED_RETENTION_DAYS` | `30` | Hard-delete invalidated generations after this many days; entries with no input references are deleted immediately |
| model profile `cache_revision` | required string/integer for cache-enabled profiles | Explicitly invalidates aliases whose provider behavior changes |

No similarity threshold, embedding model, or cache TTL variable is introduced for the
initial `extract_metrics` implementation.

## 8. Implementation

### 8.1 New code

- Add a small cache store/service under `ChenWeb/server/api/doc-processing/` with seams
  for exact lookup, validated publish/refresh, invalidation, signature construction, and
  best-effort hit accounting.
- Use `loggerutil.CreateDefaultLogger(loc)` with a new unique location ID for cache
  operations, and preserve per-call structured `kb.doc_proc_logs` telemetry from DR8.
- Add `llm_cache_mode` parsing to the run/event context without changing the defaults or
  meaning of `force` and `force_clear`.

### 8.2 `extract_metrics` integration

- Wrap `extractMetricCandidatePayloadWithFallback(...)` at the Pass 1 call sites with
  cache lookup/write behavior.
- Wrap `extractMetricPayload(...)` for `candidate_enrichment` only at the Pass 2 call
  site; do not globally cache every call through the generic extractor in phase 1.
- In `use` mode, preserve fallback ordering exactly: look up the primary model key; on a
  primary miss, call the primary model live; only if that call fails may the processor
  look up the fallback-model key before making a live fallback call. A cached fallback
  never bypasses a healthy primary model merely because the primary key missed. Other
  modes follow DR6's explicit routing. A live fallback result is stored under the actual
  fallback model fingerprint and logged as such.
- If a model profile has no immutable provider revision and no configured
  `cache_revision`, caching is disabled for that model with a warning; document
  processing continues live. Enabling caching for that profile requires adding the
  revision, not guessing model stability.
- Re-run existing annotation, normalization, deduplication, identity resolution, merge,
  persistence, and indexing on cached payloads.
- Count only actual provider requests in existing `LLMCallCount`; add separate cache hit
  and miss counts to the final processor summary.

### 8.3 Administration

Phase 1 exposes two distinct SQL/CLI operations:

- **detach/purge input:** delete that input's rows from `kb.llm_task_cache_refs`; shared
  entries remain active when another input still references them, and the ref-count
  trigger deletes an entry when the last reference disappears;
- **invalidate results:** soft-invalidate by knowledge store plus task, stage, prompt
  hash, model fingerprint, logical signature, or explicit entry ID; this affects every
  consumer of the selected result and therefore always requires knowledge-store scope.

There is no ambiguous "invalidate by input" operation. A cache-management GUI is out of
scope. Result invalidation is soft (`status='invalidated'`, timestamp, reason) so
provenance remains inspectable for the configured 30-day audit window. The same scheduled
retention mechanism used for LLM telemetry hard-deletes invalidated generations after
`DOC_PROCESS_LLM_CACHE_INVALIDATED_RETENTION_DAYS`; deleting a cache entry cascades its
references. Entries whose last input reference is deleted are hard-deleted immediately,
regardless of status or retention window.

## 9. Operational Behaviors

- Empty cache, disabled cache, lookup failure, and write failure all preserve the current
  live-LLM behavior.
- A source edit changes affected canonical chunk hashes; unchanged chunk units may still
  hit, and only changed/new units are recomputed.
- A changed title or document number changes `canonicalChunkInputText` and conservatively
  misses every affected stage unit because document context may influence interpretation.
- Rechunking may reuse a unit only when its complete canonical stage input is identical;
  overlap or line-number changes that affect serialized input cause a miss.
- Prompt, schema, normalization, effective model options, or model cache revision changes
  cause misses automatically.
- Cache hits remain scoped to one knowledge store; the cache service verifies and
  records the consuming input reference before returning the hit.
- Stop/cancellation checks occur before lookup result consumption and before any live
  call; a stopped run does not continue merely because results are cheap to load.
- `refresh` creates a new active generation only after successful validation; failed
  refreshes do not poison or remove the prior entry.
- `modify_time` changes only when result/status metadata changes (refresh, invalidation,
  expiration); hits update `last_hit_at`/`hit_count` and reference `last_used_at` without
  rewriting `modify_time`.
- No negative/error caching is performed.

## 10. Consequences

### Positive

- Exact stage hits avoid the entire provider request, not merely some prompt tokens.
- Reprocessed documents can reuse unchanged chunks while recomputing only changed or new
  chunks—the article's scoped-agent-call benefit, implemented with a provable scope.
- Results become reproducible for routine reruns with the same full dependency
  fingerprint.
- Existing provider prompt caching still lowers the cost of genuine misses.
- An empty or unavailable cache degrades safely to current behavior.

### Negative and tradeoffs

- Persistent LLM outputs increase database storage and inherit document-data security,
  backup, retention, and deletion obligations.
- The key contract must be maintained whenever prompts, model options, schemas, or
  normalization behavior change. Missing a behavior-affecting dependency can cause an
  invalid hit.
- Routine `use` mode suppresses run-to-run model variance. Experiments seeking additional
  extraction recall must use `refresh` or `off` and should be reported separately from
  production cache metrics.
- Cross-process simultaneous cold misses can still duplicate an LLM call in phase 1;
  first-valid-writer wins the cached baseline.
- Conservative exact matching produces fewer hits than semantic matching, intentionally.

## 11. Tests and Acceptance Criteria

### 11.1 Signature unit tests

- map insertion order does not change a signature;
- array order changes a signature where order is meaningful;
- run ID, event ID, timestamps, and current input record do not change a signature;
- knowledge-store ID, canonical chunk bytes, candidate batch membership/order, prompt
  contents, model cache revision/options, contract, and key version each change it;
- canonical JSON and SHA-256 output are stable across repeated runs.

### 11.2 Store tests

- complete entry lookup, expiration, invalidation, hit accounting, and result-hash
  verification;
- only validated successful outputs are inserted;
- concurrent same-key cold fills leave the first committed valid entry active;
- refresh creates exactly one new generation only after validation; failed refresh
  preserves the old active generation and its result;
- refresh compare-and-swap rejects publication when active state changed during the live
  call, including `none`→cold-fill and N→N+1 races;
- a result with multiple record references survives deletion of one input; deletion of
  the last reference deletes the result; cross-store references are rejected;
- concurrent final-reference deletion and concurrent attach/delete leave no orphan and
  never produce a negative `ref_count`;
- the invalidated-generation retention job honors its configured age and never deletes
  the active generation;
- database read/write errors fail open to the caller.

### 11.3 Processor tests

- all-hit Pass 1 makes zero candidate-extraction provider calls;
- mixed Pass 1 executes only missing chunks and restores current chunk order;
- Pass 2 keys include the canonical candidate batch and source chunk;
- changing one chunk recomputes that chunk and all changed downstream batches, while
  unchanged units still hit;
- cached payloads still pass annotation, normalization, deduplication, identity, merge,
  persistence, and indexing paths;
- primary/fallback model cache entries preserve live primary-before-fallback ordering
  and provenance; a missing cache revision disables caching but not processing;
- `use`, `refresh`, `off`, and deployment-only `write` have the behaviors in DR6/DR9;
- `force` and `force_clear` remain independent of cache mode;
- cancellation prevents cached or live result consumption after stop;
- corrupt/expired/invalid cached entries warn and fall through to the live LLM path.

### 11.4 Shadow and production acceptance

Before enabling `use`:

- shadow mode covers at least 20 representative documents and 500 stage executions,
  including all cases listed in DR9;
- shadow comparisons show zero contract-invalid baselines, zero cross-store hits, and
  zero incorrect signature-equivalence cases. An incorrect equivalence case means a
  manual/benchmark review finds that two requests sharing a logical signature differ in
  any behavior-affecting stage input or that serving the baseline would be invalid for
  the current request;
- `ValidatedStageResultV1` differences are measured and reviewed rather than assumed
  harmless;
- the paired extraction benchmark loses no gold-positive metric found by the live
  baseline and changes aggregate precision or recall by no more than one percentage
  point; the document-processing owner approves the report;
- cache metrics distinguish avoided calls from provider prompt-cache tokens;
- a rollback to `DOC_PROCESS_LLM_CACHE_MODE=off` restores current behavior without a
  migration rollback.

After enabling Pass 1, observe at least seven days and 100 Pass 1 hits. Pass 2 is enabled
only if there are zero cache-attributable correctness incidents, the same benchmark gate
still passes, and result-cache hits reduce actual Pass 1 provider calls by at least 20%
on eligible reruns. Here an eligible rerun is a Pass 1 stage execution under `use` with
a cache-enabled model and an active complete signature present at stage start; reduction
is `(eligible executions - provider calls for those executions) / eligible executions`.
Before Pass 2 serving is enabled, rerun the same named and versioned paired benchmark
with Pass 2 cache reads enabled and satisfy the same gold-positive and ±1 percentage-point
precision/recall gate. Any cross-store hit, result-hash/contract failure, or confirmed
cache-attributable extraction regression immediately rolls the deployment back to
`DOC_PROCESS_LLM_CACHE_MODE=off` pending investigation.

## 12. Documentation Impact

### Knowledge changed

- SemOS will have two distinct cache layers: provider prompt-prefix caching and a
  persistent application result cache.
- Partial reuse for authoritative document extraction means exact chunk/batch coverage,
  not embedding similarity.
- `force`, `force_clear`, and `llm_cache_mode` are independent controls.

### Documents affected

- Update `2026062501-adr-deepseek-cache.md` with a cross-reference clarifying that it
  covers provider prompt caching, while this ADR covers zero-call result reuse.
- Update `2026071002-adr-doc-processor-incremental.md` to require `refresh`/`off` for
  intentional repeated-sampling experiments.
- Update the document-processor operator/manual documentation with cache-mode behavior,
  telemetry definitions, invalidation, and rollback after implementation.
- Update the database/schema documentation for `kb.llm_task_cache` after migration.

### Intentionally undocumented until implementation

- exact Go type and filename names;
- migration timestamp;
- cache administration UI, because none is approved;
- semantic thresholds, because semantic result reuse is rejected for this scope.

No existing document becomes false merely by accepting this proposal. The two ADRs named
above become incomplete once implementation is enabled and must then be amended.

## 13. References

- [Stop Paying Your AI Agent to Do the Same Job Twice](https://dzone.com/articles/ai-agent-efficiency),
  DZone, published 2026-08-21 — source pattern: exact hash, semantic candidate lookup,
  scoped fallback, cache freshness, and force bypass.
- `KnowledgeStore/doc-repo/research/202608/2026082201-rsch-llm-prompt-cache.md` — SemOS
  analysis of structured inputs, semantic retrieval versus scope comparison, and the
  `extract_metrics` opportunity.
- `KnowledgeStore/doc-repo/adrs/202606/2026062501-adr-deepseek-cache.md` — existing
  provider prompt-prefix caching and cache-token telemetry.
- `KnowledgeStore/doc-repo/adrs/202607/2026071002-adr-doc-processor-incremental.md` —
  current force/force-clear and repeated-extraction semantics.
- `ChenWeb/server/api/doc-processing/extract-metrics.go` — current two-pass metric
  extraction, deterministic batch construction/deduplication, incremental merge, and
  LLM call telemetry.
- `ChenWeb/server/api/doc-processing/input_lines.go` — canonical chunk serialization
  used as the stable document-first LLM input.

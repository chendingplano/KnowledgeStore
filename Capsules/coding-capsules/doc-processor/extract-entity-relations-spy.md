# Deterministic Entity and Relation Extraction — Go Design

Date: 2026-09-04  
Status: Draft for review  
Implementation target: `ChenWeb`

> The requested filename uses `spy`; this document retains that filename while the
> design refers to spaCy by its correct name.

## 1. Decision

Implement the first version directly in Go. Do not create
`ChenWeb/python/extract-entity-relations/` in the initial implementation.

The referenced DZone article uses spaCy, but its demonstrated relation extractor is
not a trained relation model and does not use spaCy's dependency parser. It combines:

1. configured domain entity patterns;
2. general named-entity recognition;
3. an alias-to-canonical-name map;
4. configured relation phrases such as `depends on` and `owns`; and
5. deterministic subject/object selection.

The domain patterns, aliases, phrase matching, source-span tracking, normalization,
and subject/object selection can all be implemented cleanly in Go. A native
implementation also fits the existing Go doc-processor runtime and avoids adding a
second service boundary for an algorithm that is primarily rule based.

The existing runtime already exposes entity and relation extraction as two Phase B
operations, `extract_entity` and `extract_relation`. The new implementation will be
an alternate engine behind those logical operations, selected by configuration. It
must not be registered as a third processor that writes the same tables concurrently.

Initial engine selection:

```text
ENTITY_RELATION_ENGINE=llm       # existing behavior and default during rollout
ENTITY_RELATION_ENGINE=go_rules  # new deterministic implementation
```

Only one engine may own `kb.entities`, `kb.relations`, `.entities`, and `.relations`
for a record run.

The first release retains the doc processor's documented single-instance deployment
constraint. Switching engines requires draining the running doc-processor instance
before starting its replacement. A rolling deployment with mixed engine settings is
not supported. Before any future multi-replica deployment, persist the selected engine
in the execution plan and add record-scoped database ownership/locking; process-local
configuration alone is not a cluster-wide lock.

## 2. Why Go Is Sufficient

The article's useful production pattern is rules plus a domain dictionary, not a
spaCy-specific API. Its example adds exact domain names with `EntityRuler`, folds
aliases into canonical names, scans for configured relation phrases, and preserves
the source sentence. The article also explicitly presents the implementation as a
simple prototype and warns that its first-two-entities subject/object rule is not
universal.

spaCy remains stronger if a later version requires statistical multilingual NER,
dependency-aware syntax, or a trained relation classifier. Those capabilities are
not required to reproduce the article's baseline.

A Go NLP package was also considered. `github.com/jdkato/prose` provides pure-Go
tokenization, sentence segmentation, POS tagging, and English NER, but no domain
`EntityRuler`, dependency parser, or relation extractor. Adding that model dependency
would not remove the need for the custom rule engine. Version 1 should therefore use
the Go standard library plus a small, purpose-built matcher. A statistical Go NER
component can be evaluated later as a separate recall enhancement.

## 3. Goals

- Extract domain entities and typed relations without any LLM call.
- Preserve source line evidence for every entity and relation.
- Normalize aliases before graph construction.
- Produce the current `kb.entities` and `kb.relations` row shapes.
- Reuse current entity consolidation, relation endpoint linking, artifacts, search
  indexing, relation graph indexing, and status handling.
- Make behavior deterministic, explainable, testable, and versioned.
- Allow rule bundles to evolve without recompiling the service.
- Keep the existing LLM engine available for comparison and fallback at the
  deployment/configuration level.

## 4. Non-Goals

- Open-domain relation extraction.
- Inferring relations not explicitly stated in source text.
- Coreference resolution across paragraphs or chunks.
- Cross-document entity reconciliation; the existing reconciliation workflow remains
  responsible for that.
- Automatic translation.
- Simultaneously merging LLM and rule-engine output into the same record during the
  first release.
- Replacing Phase C indexing or the canonical relation store.

## 5. Current-System Compatibility

The source spec, `extract-entity-relation-spec.md`, describes the original combined
`extract_entity_relation` processor. Current ChenWeb code has since split it into:

| Logical operation | Current Go type | Output |
|---|---|---|
| `extract_entity` | `EntityProcessor` | `kb.entities`, `.entities` |
| `extract_relation` | `RelationProcessor` | `kb.relations`, `.relations` |

The implementation must target the current split runtime, not recreate the obsolete
combined execution path. The rule implementation should provide equivalent entity
and relation wrappers and continue to use the existing operation names so routing,
status rollups, benchmarks, and the dashboard do not need a second vocabulary.

The following existing behavior must be reused:

- chunk loading and canonical line metadata;
- `consolidateEntities` before assigning `<record_id>_ent_<seqno>` IDs;
- Phase C `linkRecordEndpoints` behavior, including provisional entities;
- `EntityRelationSQLStore.SaveEntities` and `SaveRelations`;
- `.entities` and `.relations` artifact paths;
- `ReindexEntitySearchForRecord` and `ReindexRelationSearchForRecord`;
- entity category, line-overlap, object-link, and relation-graph indexing;
- `force=false` idempotent skip and `force=true` replacement;
- `kb.inputs.status` entries keyed by `extract_entity` and `extract_relation`.

No database migration is required for the baseline design.

## 6. Proposed Code Layout

```text
ChenWeb/
├── config/entity_relation_rules/
│   └── en.json
└── server/api/doc-processing/
    ├── entity-relation-rules.go
    ├── entity-relation-rules-config.go
    ├── entity-relation-rules_test.go
    ├── extract-entity-relation.go         # accept/merge rule provenance
    └── runtime.go                         # select LLM or Go rules engine
```

The existing storage and Phase C code stays authoritative. New files contain the
extraction and rule-loading behavior; the existing store receives only the minimal
provenance and transactional-replacement extensions described below.

Use typed candidates internally and convert to the legacy `map[string]any` shape only
at the existing normalization/persistence boundary. Suggested core contract:

```go
type ExtractionRunProvenance struct {
    Engine        string
    SchemaVersion string
    BundleVersion string
}

type RuleProvenance struct {
    RuleIDs       []string
    ChunkSeqNos   []int
}

type EntityCandidate struct {
    CanonicalName string
    EntityType    string
    Aliases       []string
    Categories    []string
    Description   string
    Keywords      []string
    LineSpans     []string
    Confidence    float64
    Provenance    RuleProvenance
    ChunkSeqNo    int
    FirstLineNo   int
    SourceStart   int // original chunk-buffer byte offset
    SourceEnd     int // exclusive original chunk-buffer byte offset
    SortRuleID    string
}

type RelationCandidate struct {
    Subject, Predicate, Object string
    Description                string
    Keywords                   []string
    Categories                 []string
    SubjectLines               []string
    PredicateLines             []string
    ObjectLines                []string
    Confidence                 float64
    Provenance                 RuleProvenance
    ChunkSeqNo                 int
    FirstLineNo                int
    SourceStart, SourceEnd     int
    SortRuleID                 string
}

type EntityRuleExtractor interface {
    ExtractEntities(ctx context.Context, chunk Chunk) ([]EntityCandidate, error)
}

type RelationRuleExtractor interface {
    ExtractRelations(
        ctx context.Context,
        chunk Chunk,
        mentions []EntityCandidate,
    ) ([]RelationCandidate, error)
}
```

Constructors validate every required field. Conversion functions validate canonical
line-span syntax and confidence bounds before returning persistence maps; an invalid
candidate fails the operation instead of reaching SQL with a partial shape.

Rule-backed wrappers implement `Processor` and `PostProcessIndexer`, but deliberately
do not implement `ChunkBatchProcessor`. That coordinator exists to sequence LLM calls
for prompt-cache reuse, which the rules engine does not need, and its interface places
mutable batch state on a runtime-shared processor instance. Each rule wrapper instead
loads/processes its chunks inside `HandleEvent` and keeps all per-record state in local
variables. The immutable compiled rule index may be shared. This makes concurrent
record pipelines safe without a processor-level batch-state map or serialization.

## 7. Rule Bundle

Use versioned JSON so the loader requires no new parsing dependency. Default path:

```text
config/entity_relation_rules/en.json
```

Environment override:

```text
ENTITY_RELATION_RULES_DIR=/absolute/or/project-relative/path
```

Proposed shape:

```json
{
  "schema_version": "1",
  "bundle_version": "en-engineering-v1",
  "language": "en",
  "matching": {
    "fold_separators": ["-", "_"],
    "connectors": ["of", "and", "for"],
    "stop_words": ["a", "an", "the", "this", "that"],
    "negation_window_tokens": 2
  },
  "entities": [
    {
      "id": "payment-api",
      "canonical_name": "Payment API",
      "entity_type": "api",
      "aliases": ["payment-api", "Payments API", "payment service"],
      "categories": ["software_system"],
      "confidence": 1.0
    }
  ],
  "entity_suffix_rules": [
    {
      "id": "service-suffix",
      "suffixes": ["Service", "Worker"],
      "entity_type": "service",
      "max_tokens": 6,
      "confidence": 0.82
    },
    {
      "id": "team-suffix",
      "suffixes": ["Team"],
      "entity_type": "team",
      "max_tokens": 6,
      "confidence": 0.82
    }
  ],
  "relations": [
    {
      "id": "depends-on",
      "phrases": ["depends on", "is dependent on"],
      "predicate": "depends_on",
      "direction": "left_to_right",
      "subject_types": ["service", "api"],
      "object_types": ["service", "api", "database", "queue"],
      "categories": ["system_dependency"],
      "confidence": 0.95
    }
  ],
  "negations": ["not", "never", "no longer"]
}
```

`fold_separators` means: treat each configured separator as a comparison-token
boundary and collapse consecutive boundaries, while retaining its original bytes in
the source-span map. Thus `payment-api`, `payment_api`, and `payment api` compile to
the same two-token comparison sequence without altering original offsets. Separators
not in this list remain internal token characters.

Loader validation must reject:

- unsupported schema versions;
- duplicate entity or relation rule IDs;
- empty canonical names, aliases, phrases, types, or predicates;
- invalid confidence values;
- predicates that are not lowercase snake case;
- unsupported directions;
- an out-of-range negation window or empty matching vocabulary item;
- aliases that map to more than one canonical entity in the same bundle.

The bundle is loaded once when the production runtime is constructed, compiled into
immutable match indexes, and shared safely across concurrent record pipelines.

The complete seed bundle must cover the article fixture, not only the abbreviated
example above. It includes entity types/patterns for `service`, `api`, `database`,
`search_index`, `team`, `worker`, and `queue`, plus relation rules for `depends_on`,
`stores_in`, `owns`, `calls`, `indexes_in`, and `publishes_to`: the article's five
main predicates plus the `publishes_to` exercise, six total. Each seed rule has a
stable ID and explicit direction.

## 8. Extraction Algorithm

### 8.1 Preserve line provenance

Process the existing `Chunk.Lines`; do not flatten the source and lose metadata. Skip
`line_type = "image"`. For every retained line, preserve:

- line number;
- page number;
- overlap marker;
- original text; and
- byte offsets within a temporary chunk buffer.

The matcher must never index the original string with offsets from normalized text.
Tokenization produces tokens containing original byte start/end offsets plus a
separate normalized comparison value. Rules compile to normalized token sequences;
matches retain the original token boundaries. The offset map then resolves those
original byte spans back to canonical line spans. This remains correct when Unicode
case conversion or whitespace normalization changes byte length.

### 8.2 Entity mentions

For each non-image line:

1. Tokenize letters, numbers, and permitted internal punctuation while retaining
   original byte spans. Configured `fold_separators` create comparison-token
   boundaries; other permitted punctuation remains internal. Normalize comparison
   tokens with Unicode lowercase.
2. Apply exact canonical-name and alias matches using a trie of normalized token
   sequences with token-boundary matching.
3. Apply configured suffix rules to discover previously unlisted domain names such
   as `Checkout Service` or `Platform Team`.
4. Resolve overlaps in this order: exact catalog match, longest span, higher
   configured confidence, earliest source position.
5. Normalize every mention to its configured canonical name when available.
6. Emit one mention record with type, aliases, categories, confidence, rule ID, byte
   offsets, and source line.

A suffix rule includes the suffix token. It may extend left by at most `max_tokens-1`
tokens within the same clause while tokens are proper-name-like: initial uppercase,
all-uppercase acronym, number/model token, or a configured connector such as `of` or
`and`. It stops at punctuation, a configured stop word/determiner, the line boundary,
or the first token that is neither proper-name-like nor a configured connector. No
POS tag or implicit verb detection is used. At least one token must precede the
suffix. Its canonical name is the trimmed original source span. Exact catalog/alias
matches always win an overlap. These constraints and the stop-word/connector lists are
part of the versioned bundle and must have false-positive fixtures.

Do not use a generic "capitalized words are entities" rule in version 1; its expected
precision is too low for graph construction.

After all chunks are processed, convert mentions to the existing entity map shape and
call `consolidateEntities`. Overlap copies from chunking must merge into the same
entity and union their line spans.

Field mapping:

| Existing field | Rule-engine value |
|---|---|
| `entity` | canonical name |
| `entity_type` | configured type |
| `aliases` | observed/configured aliases excluding canonical name |
| `desc` | first source sentence or line containing the entity |
| `keywords` | canonical name tokens plus entity type, deduplicated |
| `line_spans` | all evidence lines |
| `confidence` | highest matching rule confidence |
| `entity_categories` | configured categories |
| `_en` fields | empty for the English v1 bundle |

### 8.3 Relations

`extract_relation` cannot read uncommitted output from the concurrently running
`extract_entity` operation. Its rule wrapper therefore runs the same immutable entity
matcher locally for each chunk, passes those ordered mentions explicitly to
`RelationRuleExtractor.ExtractRelations`, and persists only relation candidates. Phase
C later links those canonical endpoint surfaces to the independently persisted
entities.

Relation phrases are compiled and matched as normalized token sequences, never raw
substrings. When phrases overlap, prefer the longest sequence, then highest confidence,
then stable rule ID. For each surviving occurrence:

1. Bound the local clause by newline or strong punctuation (`.`, `;`, `:`, `?`, `!`).
2. Select the nearest compatible entity ending before the phrase as subject.
3. Select the nearest compatible entity starting after the phrase as object.
4. Enforce optional subject/object type constraints.
5. Reject missing endpoints, identical endpoints, and matches with a configured
   negation ending within two tokens before the phrase (ignoring punctuation).
6. Apply `direction = left_to_right` or `right_to_left`. Passive forms such as
   `is owned by` are separate phrase rules using `right_to_left`; the engine must not
   infer passive voice.
7. Emit endpoint and predicate line spans separately.

The closest candidate is measured by intervening token count. If two compatible
candidates on the same side have equal distance, overlap the same boundary, or cannot
be ordered unambiguously, reject the relation and increment the ambiguous counter.

This intentionally improves on the article's "first two entities in the text"
heuristic while preserving its transparent verb-phrase approach.

Field mapping:

| Existing field | Rule-engine value |
|---|---|
| `subject` / `object` | canonical endpoint names |
| `predicate` | configured lowercase snake-case predicate |
| `desc` | exact source clause containing the triple |
| `keywords` | predicate plus endpoint names, deduplicated |
| `subject_lines` | subject evidence lines |
| `predicate_lines` | relation phrase evidence lines |
| `object_lines` | object evidence lines |
| `line_spans` | union of the three evidence sets |
| `confidence` | relation confidence multiplied by the lower endpoint confidence |
| `relation_categories` | configured categories, if any |
| `_en` fields | empty for the English v1 bundle |

Relation endpoint IDs remain empty during Phase B. The existing Phase C linker owns
`subject_entity_id` and `object_entity_id` assignment.

### 8.4 Determinism and deduplication

Within each `HandleEvent`, store per-chunk results by chunk index rather than appending
from concurrent workers. Flatten them only after all workers finish, sorted by the
candidate's `ChunkSeqNo`, `FirstLineNo`, `SourceStart`, `SortRuleID`, and canonical
name. `SourceEnd` is the final tie-breaker. This avoids scheduler-dependent IDs, and
the typed candidate contract makes every sort key explicit.

Deduplicate relations by canonical subject, predicate, canonical object, and canonical
document line spans. Never use chunk-local byte offsets as the cross-chunk dedupe key.
Repeated executions with the same input and bundle must produce identical normalized
rows and IDs. Tests compare artifacts after removing time-valued fields that the
shared persistence path intentionally regenerates.

## 9. Language Behavior

Version 1 supports English only. This is consistent with the article's example and
avoids pretending that English relation phrases work across languages.

- `DocMetadataInputRecord.SourceLanguage` is authoritative when populated. Both rule
  processors load the record during initialization inside `HandleEvent` and call the same
  `resolveRuleLanguage` helper.
- If the record language is English, run the `en` bundle.
- If the record language is unknown, inspect a bounded prefix of non-image chunk text.
  Select English only when at least 90% of its Unicode letter runes are Latin and the
  sample contains at least 20 letters; otherwise fail with an explicit
  undetermined-language error.
- If the record is known to be non-English and no matching language bundle exists,
  persist a failed processor status. Sibling processors continue normally.

Failure is preferred to silent empty success because missing graph data is otherwise
hard to detect. Additional languages are added as independent rule bundles containing
their own aliases, suffix rules, relation phrases, direction, and English canonical
labels. No automatic translation is performed. A valid zero-match run is successful
only after a supported language has been resolved; this is distinct from failure to
select a language.

## 10. Persistence and Provenance

Reuse the existing table and artifact schemas. Record deterministic provenance as:

```text
model_name = "go_rules"
prompt_name = "<bundle_version>"
```

Although `prompt_name` is historically LLM-oriented, using it for the versioned rule
bundle avoids a migration and preserves the current run metadata surface. Extend the
existing `ext_info` JSON written by `SaveEntities` and `SaveRelations` with:

```json
{
  "extraction_engine": "go_rules",
  "rules_schema_version": "1",
  "rules_bundle_version": "en-engineering-v1",
  "matched_rule_ids": ["payment-api", "depends-on"]
}
```

Add `RunProvenance ExtractionRunProvenance` to `SaveEntitiesRequest` and
`SaveRelationsRequest`; it contains only engine/schema/bundle identity. Keep
row-specific `RuleProvenance` on each candidate and its legacy map during conversion.
The stores combine run identity with that row's rule IDs/chunk sequences in
`ext_info`; request-level values never contribute rule IDs to individual rows. The
stores do not accept arbitrary caller JSON. Current `language`, `schema_version`, and
`chunk_seq_no` keys remain present.

Extend `mergeEntityGroup` so rule candidates do not lose provenance during the current
map-rebuilding consolidation step. When it combines mentions, `matched_rule_ids` and
`chunk_seq_nos` are sorted unique unions. `chunk_seq_no` remains the earliest sequence
number for backward compatibility. Relations normally carry one rule ID and chunk,
but use the same sorted-union rule after deduplication. This makes provenance stable
across worker completion order. LLM candidates without these keys retain current
behavior.

The source clause in `desc` and the line-specific fields satisfy the article's source
tracking recommendation. Phase C continues to build richer `entity_context` and graph
connections.

## 11. Runtime and Failure Semantics

When `ENTITY_RELATION_ENGINE=go_rules`:

- missing or malformed rule configuration fails runtime construction;
- a record-level unsupported language writes a failed status for the affected
  operation;
- cancellation is checked before each chunk and during long match loops;
- `ErrPipelineStopped` uses the existing stopped-status path;
- one malformed rule must never be ignored;
- a valid run with zero matches is successful and logs zero counts;
- individual chunks do not fail independently due to model/network errors because the
  engine performs no network calls;
- storage, artifact, and indexing errors retain existing failure behavior.

Two artifact behaviors are deliberate compatibility changes: zero-result runs now
write empty arrays, and a post-commit atomic-rename failure marks the operation failed
instead of being warning-only. Other existing artifact/indexing failure semantics stay
unchanged.

Successful zero-match runs write `[]` to the corresponding artifact file. Update the
shared artifact writer, which currently returns early for an empty slice, so callers
can distinguish "processed with no matches" from "not processed". This behavior must
be applied consistently to both engines and covered by regression tests.

For `force=true`, do not delete good rows before extraction. Add explicit store methods
`ReplaceEntities(ctx, req)` and `ReplaceRelations(ctx, req)`. Each starts a database
transaction, deletes that record's prior rows, inserts every validated replacement,
and commits; any insert error rolls back to the prior good rows. `Save*` remains the
non-replacement path.

Serialize the complete artifact to a sibling temporary file before starting the
database transaction. After a successful commit, atomically rename it over the final
artifact. If rename fails, the database remains authoritative, the operation is marked
failed, and the temporary file is retained for diagnosis/retry; the previous final
artifact is not overwritten. A forced retry rebuilds both stores. Entity and relation
operations still commit separately, as they do today; consumers must use pipeline
status and only treat a completed record as a consistent generation. A fully atomic
database/filesystem or two-operation generation would require a separate design and
is out of scope.

There are no LLM permits, prompts, cache sequencing, fallback models, or LLM-call log
rows for this engine.

## 12. Observability

Use a new `CreateDefaultLogger` location when implementation begins, following the
workspace logging rule. Existing processor spans remain named for the logical
operations.

Log one structured summary per operation with:

- `record_id`;
- `engine=go_rules`;
- rule bundle and schema versions;
- chunks and lines processed;
- entity mentions, consolidated entities, and relations emitted;
- rejected ambiguous relations;
- unsupported-language outcome;
- elapsed milliseconds.

Do not log full document lines. Rule IDs and counts are sufficient for routine
diagnosis; source evidence remains in the artifacts and database.

## 13. Configuration and Routing

Keep `extract_entity` and `extract_relation` in
`[doc-processing].required_processors`. Engine selection is process-wide for the first
release so two concurrent pipelines cannot choose conflicting writers.

`NewProductionRuntime` must validate `ENTITY_RELATION_ENGINE`:

| Value | Behavior |
|---|---|
| empty / `llm` | construct current LLM-backed processors |
| `go_rules` | construct rule-backed processors |
| anything else | fail fast at startup |

Operational rollout must stop intake, wait for in-flight pipelines, stop the old
instance, change the setting, and then start the new instance. Mixed-engine rolling
deployment is prohibited for the single-instance baseline.

No capsule pipeline row, dashboard operation, canonical operation alias, or routing
policy change is needed because the logical processor names do not change. The capsule
and entity/relation spec still need an implementation note documenting the alternate
engine and its non-LLM behavior.

## 14. Test Plan

### 14.1 Pure unit tests

- rule-bundle validation, including alias conflicts and invalid predicates;
- case and whitespace normalization without corrupting source offsets;
- exact entity matching and alias canonicalization;
- suffix-rule extraction;
- overlap priority and longest-match behavior;
- UTF-8 byte-offset-to-line mapping;
- active and passive relation direction;
- nearest compatible subject/object selection;
- type constraints;
- negation rejection;
- multiple relations in one line;
- relation and entity deduplication across overlapped chunks;
- stable ordering and stable IDs;
- cancellation.

### 14.2 Processor tests

- engine selection in `NewProductionRuntime`;
- rule wrappers do not satisfy `ChunkBatchProcessor` and keep per-run state local;
- `force=false` skip and `force=true` delete-before-save;
- entity and relation status transitions;
- unsupported-language failure;
- existing `SaveEntities` / `SaveRelations` field mapping;
- merged `ext_info` provenance;
- transactional replacement preserves prior good rows on extraction/save failure;
- zero-result runs write explicit empty artifacts;
- `.entities` / `.relations` artifact compatibility;
- Phase C endpoint linking and provisional entity behavior;
- search and relation-graph indexing remain callable with rule output;
- verify no LLM client call or permit acquisition occurs.

### 14.3 Article fixtures

Add the article's examples as gold fixtures. They must produce at least:

```text
Checkout Service --depends_on--> Payment API
Payment API --stores_in--> PostgreSQL
Platform Team --owns--> Payment API
Recommendation Service --calls--> Catalog API
Catalog API --indexes_in--> Elasticsearch
Search Team --owns--> Catalog API
Billing Worker --publishes_to--> Kafka
```

Also add adversarial fixtures where:

- more than two entities occur in a sentence;
- relation order differs from entity discovery order;
- a relation is negated;
- aliases occur at both endpoints;
- the same source line appears in overlapped chunks;
- two same-type candidates make an endpoint ambiguous.

### 14.4 Benchmark gate

Run both `llm` and `go_rules` against the existing gold doc-processor corpus. Report
entity and relation precision, recall, F1, unmatched gold items, extractions without
gold support, elapsed time, and LLM usage/cost.

Because engine selection is exclusive and both engines use the same canonical tables,
benchmarking must use isolated captures: run each engine against a cloned test database
and a distinct temporary `ARTIFACT_DIR`, export normalized rows/artifacts, then compare
the two exports offline. Never alternate engines against the same live record set.

The rules engine may become the default only when:

- article fixtures are exact;
- entity precision is at least 0.95;
- relation precision is at least 0.90;
- entity recall is at least 0.80 on the intended controlled-document corpus;
- relation recall is at least 0.75 on that corpus;
- two repeated runs produce identical normalized output; and
- all existing entity/relation persistence and Phase C tests pass.

If precision passes but recall does not, keep `llm` as default and expand the governed
rule bundle. Do not silently combine engines until merge/provenance semantics have a
separate design.

## 15. Implementation Plan

### Phase 1 — Gold contract and rules

1. Add article and adversarial gold fixtures.
2. Define the versioned JSON schema and initial English engineering bundle.
   The seed bundle must enumerate every article entity type, the five main article
   predicates, and the exercise's `publishes_to` predicate.
3. Implement strict loading, normalization, and conflict validation.
4. Verify with loader and fixture tests.

### Phase 2 — Pure extraction engine

1. Implement line/offset mapping.
2. Implement exact and suffix entity matchers.
3. Implement alias normalization and deterministic mention ordering.
4. Implement relation phrase matching and endpoint selection.
5. Implement confidence, evidence, and deduplication.
6. Verify all pure tests and benchmarks without database access.

### Phase 3 — Doc-processor integration

1. Add non-`ChunkBatchProcessor` rule-backed entity and relation wrappers with all
   run state local to `HandleEvent`.
2. Reuse current stores, consolidation, status, artifact, and Phase C paths.
3. Add transactional `ReplaceEntities` / `ReplaceRelations` and explicit empty
   artifact writes.
4. Add typed-to-legacy conversion, extend consolidation provenance merging, and add
   rule provenance to `ext_info`.
5. Select the engine in `NewProductionRuntime` with startup validation.
6. Update the entity/relation spec and implementation notes to match the current split
   runtime and document `go_rules`.
7. Verify targeted Go tests and `mise build-server`.

### Phase 4 — Evaluation and rollout

1. Run the gold corpus with both engines.
2. Review false positives and false negatives; update rules, not extraction code, when
   the issue is domain vocabulary.
3. Deploy with `llm` still the default.
4. Enable `go_rules` in staging and compare status, latency, graph quality, and search
   output.
5. Promote only after the benchmark gate passes.

### Phase 5 — Required completion checks

Before implementation is considered complete:

```text
What knowledge changed?
Which docs/specs/ADRs/tests are affected?
Which docs were updated?
Which docs are now stale?
What was intentionally left undocumented?
```

If `ChenWeb/go.mod` changes in a later implementation, run workspace-aware dependency
sync and verify dependent builds as required by the workspace instructions. The
baseline standard-library design does not add a module dependency.

## 16. Python/spaCy Contingency

Create `ChenWeb/python/extract-entity-relations/` only if benchmarking demonstrates a
required capability that the governed Go rules cannot reasonably provide, such as
multilingual statistical NER or dependency-aware relations.

If activated, the Python process should load spaCy and all rule bundles once at
startup and expose a small versioned extraction API. The Go processor must remain the
owner of record lookup, status, database writes, artifact files, IDs, Phase C linking,
and indexing. The Python response should contain only extracted candidates plus source
offsets/lines; it must not write ChenWeb tables directly.

Minimum service layout:

```text
ChenWeb/python/extract-entity-relations/
├── pyproject.toml
├── uv.lock
├── README.md
├── mise.toml
├── service.py
├── extractor.py
├── rules/
└── tests/
```

The Go wrapper would require health/readiness checks, request timeouts, cancellation,
response schema validation, and a clear failed-status path. This contingency adds
deployment and operational cost, so it is not part of the initial implementation.

## 17. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Rules miss unknown entities | suffix rules, governed catalog expansion, gold-corpus recall tracking |
| Phrase match assigns wrong endpoints | nearest compatible spans, type constraints, ambiguity rejection |
| Negated text creates false edges | explicit local negation guard and adversarial tests |
| Rule changes silently alter the graph | bundle version in every row, fixture diff, staged rollout |
| LLM and rules engines overwrite each other | one process-wide engine, same logical operations, startup validation |
| Non-English records appear empty | explicit unsupported-language failure, never silent success |
| Existing spec describes obsolete combined runtime | update spec/impl notes during integration before claiming completion |

## 18. Open Questions for Review

These do not block the baseline implementation but should be answered before enabling
`go_rules` by default:

1. Which governed source should own production entity aliases: a checked-in bundle,
   `kb.object_nodes`, an external service catalog, or a generated snapshot?
2. Should unsupported languages be a failed operation, as proposed, or should routing
   prevent the processor from being selected for those records?
3. Are the proposed precision/recall gates appropriate for the intended document
   classes?
4. Should rule-backed results and LLM-backed results eventually coexist in separate
   candidate tables for side-by-side human review?
5. Is `prompt_name` acceptable for the rule bundle version, or is a dedicated
   `extraction_method`/`rules_version` schema change preferable?

## 19. Sources

- [DZone: Entity and Relationship Extraction With spaCy](https://dzone.com/articles/entity-relationship-extraction-spacy) — domain entity rules, alias normalization, relation phrases, source tracking, and production cautions.
- [spaCy: Rule-based matching](https://spacy.io/usage/rule-based-matching/) — `EntityRuler`, token patterns, and dependency matching capabilities.
- [spaCy: Linguistic features](https://spacy.io/usage/linguistic-features) — model-backed NER, POS, morphology, and dependency parsing.
- [jdkato/prose](https://github.com/jdkato/prose) — available pure-Go NLP stages and their English-only scope.
- [`+CAPSULE.md`](+CAPSULE.md) — ChenWeb doc-processor lifecycle and new-processor checklist.
- [`extract-entity-relation-spec.md`](extract-entity-relation-spec.md) — persistence and artifact compatibility target.

Web sources accessed 2026-09-04.

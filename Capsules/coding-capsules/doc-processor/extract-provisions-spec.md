# 1. Extract Provisions Processor

This is a Doc Processor ('spec-doc-processor.md'). This processor extracts normative provisions
(or 'provisions' for short) from standards, regulatory documents, or similar documents.

A provision includes requirements, obligations, prohibitions, permissions, and
recommendations.

# 2. Input

- record_id: the value of kb.inputs.id, identifies the record to process
- `EXTRACT_PROVISIONS_INPUT` (default `"chunks"`): controls the unit fed to the LLM.
  - `"chunks"` (default): use chunks produced by the Chunking Processor. Each chunk's lines are converted with `markedLinesToJSON`.
  - `"blocks"`: use blocks produced by the Blocking Processor (refer to `spec-blocking.md`). Each block's lines are converted with `blockLinesToJSON`.

# 3. Workflow
- At the start of processing, upsert the following entry to `kb.inputs.status`:
```json
{
  "operation": "extract_provisions",
  "start_time": "yyyymmdd hh:mm:ss",
  "proc_status": "running"
}
```
- Depending on `EXTRACT_PROVISIONS_INPUT`, iterate over chunks (default) or blocks. For each unit, use the EXTRACT_PROVISIONS_MODEL_NAME model with the EXTRACT_PROVISIONS_PROMPT prompt to extract provisions. Units may be processed concurrently up to `EXTRACT_PROVISIONS_MAX_TASKS` at a time (default 1, sequential). Results are collected in unit order regardless of completion order.
- Put stable extraction instructions before unit text to support provider prompt caching across units. When `MODEL_DEFAULT_REASONING_POLICY` is `no-reasoning`, disable thinking for both primary and fallback models; otherwise retain each model's configured thinking setting.
- Ambiguous artifact-object resolution uses its own configured model and explicitly disables provider thinking for every resolution call. This resolver is also shared by other artifact processors.
  - `"chunks"`: convert lines with `markedLinesToJSON`
  - `"blocks"`: convert lines with `blockLinesToJSON`
- The LLM generates zero or more provisions for each block. 
- Provisions are identified by `prov_id`, using the format `<record_id>_prv_<sequence_number>`. The sequence number starts at 1 within the input record.
- If primary extraction fails and the fallback model also returns an empty/truncated JSON response (for example `unexpected end of JSON input` with an effectively empty payload), treat that block as a successful empty extraction rather than a processor failure.
- After processing all blocks, save all the extracted provisions from all the blocks to the table `kb.provisions` (refer to "Output Storage" section).
- Save all extracted provisions to a `.provisions` artifact file (refer to "Output Storage" section).
- Upsert the following entry to kb.inputs.status if failed:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "extract_provisions",
    "proc_status":"failed",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "error":"error-msg",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

Otherwise, upsert the following element to kb.inputs.status:
```json
  {
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "extract_provisions",
    "proc_status":"success",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
  },
```

The expanded provision format is:
```json
{
  "language": "<detected_language>",
  "provisions": [
    {
      "name": "<provision name>",
      "name_en": "<provision name>",
      "type": "mandatory",
      "provision": "<original provision text>",
      "provision_en": "<English translation or same as original if English>",
      "provision_desc": <the description about the provision>,
      "provision_desc_en": <the English translation of provision_desc>,
      "source_line_spans": ["20", "25-29"],
      "context":"<the context>",
      "context_en":"<the English translation of the context if its input lanuage is not English>",
      "subject":"<the provision's subject>",
      "subject_en":"<the provision's subject>",
      "location_type":"<the location type>",
      "keywords": ["keyword", "keyword"...],
      "keywords_en": ["keyword", "keyword"...],
      "confidence": 0.0,
      "is_explicit": true or false,
      "need_verify": true or false,
    }
  ]
}
```

`source_line_spans` uses canonical line-only spans. Each value MUST be either a
single line number such as `"15"` or an inclusive line range such as `"15-18"`.
Do not include page numbers or use `<page_number>:<line_number>` values such as
`"4:48"`.

### Statement boundaries and source review (v7, 2026-11-07)

The default prompt is `prompt-extract-provisions-v7.md`. It retains v6's source-only
compact v2 wire format and existing storage fields. The normative unit follows the
released provision benchmark rules (version 1.0.0): one normative statement per
row, including imperative procedure steps and implicit requirements. Separate
consecutive sentences and changes of bound subject or provision type; retain
connected actions/properties and alternative conditions of the same subject.
Requirement prose in table cells is included; invoked numeric value tables,
definitions, scope, reference boilerplate and pure descriptive text are excluded.
Subjects identify the party bound or object constrained, independently of the
regulated objects extracted in `objects`.

V7 reviews units with multi-clause text, table/list-item input, or an empty draft
with normative cues. `EXTRACT_PROVISIONS_REVIEW_PROMPT` defaults to
`prompt-audit-provision-extraction-v1.md`. The same selected extraction model
reviews the original source, draft and punctuation-separated source clause hints,
then replaces the draft with a complete corrected v2 response. Clause hints keep
original line numbers and delimiters; they are not automatic provision splits.
The review must group fragments about the same subject and preserve conditions.
Legacy/custom extraction prompts retain single-pass behavior. Review configuration
or response failure fails the unit rather than silently accepting the draft.

Both initial extraction and review are logged under their own prompt/activity,
with their own payload and cache counters. Review calls count in `llm_call_count`.
The review always uses the compact contract regardless of its configured filename.
This adds one logical call per reviewed unit; actual provider retries are separate.

After normalization, discard rows with no evidence on a normal/owned source line;
retain rows combining owned and overlap evidence. Apply this guard in chunk,
block and batch paths. Deduplicate identical normalized text on the same canonical
line spans, ignoring terminal sentence punctuation and repeated whitespace while
preserving word boundaries. Different statements on the same line and identical
wording at different locations remain separate.

Batch results occupy their source chunk indexes, independent of completion order.
A missing/failed payload is distinct from a successful response containing zero
provisions. If every payload failed or is absent, do not finalize as a successful
empty extraction.

V7 improves model behavior but does not guarantee complete or correctly segmented
output. The isolated record-416 evaluation and its remaining errors are documented
in `extract-provisions-impl.md`. No schema migration or shared API change is needed.
Existing stored rows are not rewritten; rebuild/restart the processor and explicitly
rerun extraction to replace them.

### Source-only short LLM response (v6)

V6 introduced the source-only response; the default v7 retains this strict v2
wire response: `{"v":2,"l":"zh","p":[...]}`. `l` is the source language and `p`
is the provision array (including `[]` for a valid extraction with no provisions).
The processor expands short fields before the existing normalization and storage
paths. Database and artifact-file field names remain unchanged.

No translations are generated. Text, descriptions, context, subjects, keywords,
category paths, and object names/aliases/acronyms remain in the source language;
foreign names and identifiers already in the source are retained. Nonempty
descriptions, context, keywords, aliases, and acronyms are not discarded.

Provision keys:

| Key | Expanded field | Required |
|---|---|---|
| `n` | name | yes |
| `t` | type | yes |
| `x` | provision | yes |
| `s` | source_line_spans | yes, nonempty |
| `lt` | location_type | yes |
| `q` | confidence, number in [0,1] | yes, including zero |
| `f` | packed boolean flags | yes, including zero |
| `d` | provision_desc | omit only when empty |
| `c` | context | omit only when empty |
| `u` | subject | omit only when empty |
| `k` | keywords | omit only when empty |
| `o` | objects | omit only when empty |
| `g` | category_paths | omit if unavailable; preserve explicit `[]` |

Object keys: required `n` = object_name, `t` = object_type, `r` = object_role,
`s` = nonempty source_line_spans, `q` = confidence. Optional empty fields are
`d` = description, `a` = aliases, and `y` = acronyms. There is no evidence quote
field: the object's explicit spans are its evidence location, without a second
duplicate span attribute. Object spans are never inherited in v2.

Single-line spans are integers (e.g. `[143]`); ranges remain inclusive strings
(e.g. `["150-151"]`). The decoder also accepts canonical quoted single-line
numbers, but the prompt requests integers. Every supplied span must be valid;
mixed valid/invalid spans, nulls, empty lists, nonpositive/fractional line numbers,
and reversed ranges are rejected. Validation checks canonical positive line
numbers, not that they occur in this particular input unit.

Enum codes:

- Provision type: `m` mandatory, `r` recommended, `o` optional.
- Location: `s` sentence, `p` paragraph, `b` bullet, `tr` table_row,
  `tc` table_cell, `hc` heading_context, `mx` mixed. Decoder compatibility code
  `li` preserves the old `list-item` value; the current prompt requests `b`.
- Object type: `eq` equipment, `mat` material, `sys` system, `proc` process,
  `org` organization, `per` person, `loc` place, `doc` document, `con` concept,
  `oth` other.
- Object role: `reg` regulated_object, `tgt` requirement_target, `part` component,
  `par` parent_system, `oth` other.

`f` packs two booleans: bit 0 (value 1) is `is_explicit`; bit 1 (value 2) is
`need_verify`. Thus 0 means neither, 1 explicit only, 2 verify only, 3 both.
Flags outside 0–3, missing flags, unknown codes/attributes, translation attributes,
object quote attributes, and invalid confidence values are rejected. Empty
optional strings/lists expand to their existing empty equivalents. Presence of
category lists retains its existing meaning.

The same v2 schema validates both structured extraction (with provider retries)
and ordinary JSON responses. The built-in v6 prompt requires v2 output; it cannot
silently accept the old verbose/translated shape. Explicitly selected old/custom
prompts keep legacy/v1 support. Versioned decoding copies data rather than mutating
the captured provider response.

Native English values are copied server-side into existing English storage
fields (not translated), preserving English source text under the existing
English storage convention. Native Chinese object names likewise fill the
Chinese name field without asking the LLM to repeat them. Other-language
translations remain absent. Object evidence quotes stay absent; citations use
the retained spans.

### Legacy compact LLM response (v4/v5)

The previous prompt `prompt-extract-provisions-v5.md` remains supported when
explicitly selected. Its response adds
`"output_format": "compact-v1"` at the top level, alongside `language` and
`provisions`. The versioned prompt owns the field schema for both chunk and block
input; the processor does not append a second schema.

Before normalization, restore omitted values only for responses marked
`compact-v1`. Legacy responses (including explicitly selected v3/custom prompts)
retain their existing interpretation, except that every extracted provision must
now pass source-evidence validation regardless of prompt version. The expansion
rules are:

- Missing optional provision strings become `""`; missing `keywords` and
  `keywords_en` become `[]`; missing `objects` becomes `[]`.
- Missing object `confidence` inherits the parent provision's value. Retain a
  different confidence value. The decoder also supports missing object
  `source_line_spans` inheriting the parent's spans for compatibility with v4;
  v5 requires explicit nonempty spans on both provisions and objects and does not
  request span compression.
- For Chinese response languages (`zh`, `zh-*`, or `Chinese`, case-insensitive),
  missing `object_name_zh` inherits `object_name`. For other languages it becomes
  `""`. A different Chinese translation must be emitted explicitly.
- Other missing object strings become `""`; missing `aliases` and `acronyms`
  become `[]`.
- Presence controls expansion: explicit values, including empty strings, empty
  arrays, zero, false, and null, are not replaced. The prompt forbids null as an
  omission mechanism. Inherited fields whose intended value is empty must be
  emitted explicitly to suppress inheritance.
- Category lists retain their existing missing-versus-empty distinction. Do not
  omit an explicitly empty `category_paths` or `category_path_en` array.

Do not omit provision text, source spans, type, confidence, `is_explicit`, or
`need_verify`. Descriptions, translations, evidence quotes, nonempty aliases,
acronyms, and context remain part of extraction. Compression must not merge
independent provisions.

Every provision must have at least one usable source line span before compact
expansion and before normalization/storage. Missing, null, empty, or wholly
unusable spans make the whole unit's response invalid; do not fabricate source
evidence or silently save/drop the affected provisions. The structured contract
requires a `source_line_spans` array with at least one item on each provision,
enabling schema-validation retries on the configured model. Common response
validation also checks that the existing line-span normalizer produces nonempty
spans, including for plain JSON clients and legacy prompts. Invalid primary
responses follow the existing fallback path; if fallback evidence is also invalid,
the unit fails rather than becoming a successful empty extraction.

Expansion copies response maps so provider-captured data remains compact. The
expanded response then follows the existing normalization, storage, object
resolution, search, and artifact-writing paths. No storage schema changes are
required. Existing downstream normalization rules still apply (for example,
artifact-object normalization treats zero confidence as the parent's confidence).

## 3.1 Index Provisions
Provision indexing runs after every doc processor for the record has finished.
This is required because provision indexing reads other processors' artifacts
(semantic projections, topics, scene blocks, metrics, entities, inventory items, and
their `kb.search_artifacts` rows), which may not exist yet while the provision processor is
still running. See the doc-processor capsule's "Post Process" section.

Indexing establishes the following outputs (implemented in
`ProvisionsProcessor.PostProcessIndex`):

| Output | Storage |
|--------|---------|
| the provision row in the search registry | `kb.search_artifacts` (via `ReindexProvisionSearchForRecord`) |
| relate provision to line-overlapping artifacts (entities, metrics, inventory_items, topics, semantic_projections) | `kb.artifact_connections` (§3.1.1) |
| relate category path to provision | `provisions.txt` under the matching category paths in `ARTIFACT_WEB_DIR` (§3.1.4) |

Notes:

- The chunk→provision `has-provision` line-overlap edges are written earlier, in Phase B, by
  the extractor (`WriteLineOverlapConnectionsFromRegistry`); they are not repeated here.
- `connected_artifacts` for a provision is **computed on demand** by the
  `kb.connected_artifacts(record_id, 'provision', source_row_id)` SQL function; it is **not**
  materialized as a column or written by indexing (see §3.1.3).
- Semantic provision↔provision similarity is **not** materialized — it is computed live at
  read time by the provisions document reviewer (`FindSimilarArtifactsOnTheFly`).

### 3.1.1 Line-Overlap Artifact Edges

These edges make intra-document, line-overlapping artifacts explicitly traversable in
`kb.artifact_connections`. They are built deterministically at index time — no LLM or hybrid
search is involved. They exist so the document reviewers can start from a provision and reach
the metrics/entities/etc. that share its lines (and vice versa, since a read matches either
endpoint).

For each provision `P` in the record being indexed:

1. Find every artifact in the **same document** whose line spans overlap `P`'s, grouped by
   type `T ∈ {inventory_item, entity, metric, topic, semantic_projection}` → the anchors.
   Overlap is computed by self-joining `kb.search_artifacts` on the GiST-indexed
   `line_range && line_range` operator, so both endpoints are read from the registry and use
   their canonical `artifact_id`s.
2. For each overlapping artifact (anchor) `X` of type `T`, upsert one edge to
   `kb.artifact_connections`:
   - `source_type = T`, `source_id = X.artifact_id`, `source_record_id = record_id`
   - `target_type = 'provision'`, `target_id = P.prov_id`, `target_record_id = record_id`
   - `relation_name = '#shared_artifact'`
   - `relation_method = 'line-overlapped-artifact'`
   - `confidence = 1.0` (deterministic overlap)
   - `extra_info` containing at least `{"source":"extract_provisions","anchor_type":T}`

The overlapping anchor is the **source** and the provision is the **target**; because both
share lines, these edges are always intra-document (`source_record_id = target_record_id =
record_id`).

**Idempotency.** Rebuilt each run by `ReplaceSharedArtifactEdges`, which deletes the record's
existing edges scoped to `target_type = 'provision'` (plus
`relation_method = 'line-overlapped-artifact'`, `relation_name = '#shared_artifact'`), then
inserts the fresh set. The delete is scoped by target family so parallel Phase-C family runs
never clobber each other's edges.

> Cross-family note: when these edges are later added for the other families (metrics,
> entities, …), an overlap between two of them (e.g. a provision and a metric) will be written
> once by each family's run, in opposite directions. That is tolerated — reviewers match
> either endpoint — but a canonical single-direction rule may be introduced when the other
> families are done.

### 3.1.2 Search Artifact Row

Each provision is registered in `kb.search_artifacts` (already implemented by
`ReindexProvisionSearchForRecord`).

Rules:

- `artifact_type` is `provision`
- `artifact_id` is `kb.provisions.prov_id`
- `input_record_id` is `kb.provisions.input_record_id`
- `source_line_spans` is copied from `kb.provisions.source_line_spans`
- search text is the de-duplicated provision text used to populate the row's `search_document`

### 3.1.3 Connected Artifacts (on demand)

`connected_artifacts` for a provision is **not** stored. The per-family
`connected_artifacts` columns were removed and replaced by the
`kb.connected_artifacts(record_id, 'provision', source_row_id)` SQL function, which returns
the overlap set at read time:

```json
{
  "chunks": ["chunk_id"],
  "semantic_projects": ["proj_id"],
  "topics": ["topic_id"],
  "scenes": ["scene_id"],
  "metrics": ["metric_id"],
  "entities": ["entity_id"],
  "inv_items": ["inv_item_id"]
}
```

- An artifact is connected when it shares at least one line with the provision.
- The function sources overlaps from `kb.chunk_ranges` and the registry `line_range` columns.
- The same overlap facts are also materialized as traversable edges by §3.1.1; indexing does
  **not** populate any `connected_artifacts` column.

### 3.1.4 Index Provisions by Category Paths

(Already implemented by `IndexProvisionsForRecord`.) Use `kb.provisions.source_line_spans` to
find semantic projection category paths:

```text
kb.provisions.input_record_id = kb.semantic_projections.input_record_id
AND kb.provisions.source_line_spans overlaps kb.semantic_projections.line_spans
```

Return `kb.semantic_projections.category_paths_en`.

Rules:

- For each returned category path, index the provision the same way semantic projections are indexed.
- Save provision IDs in `provisions.txt` under the matching category path.
- Each `provisions.txt` entry uses `kb.provisions.prov_id`.
- Provisions with no matching category path are logged (the config sets
  `WarnOnMissingCategoryPaths`), not treated as a hard error.

### 3.1.5 Indexing Provisions to Objects
Provisions mention artifact objects through `kb.provisions.prov_id` = `kb.artifact_objects.artifact_id`.
Artifact objects connect to object nodes through `kb.artifact_objects.object_id` = 
`kb.object_nodes.object_id`. 

For each provision, add a record to `kb.artifact_connections`:
  - `source_type = 'provision'`
  - `source_id = kb.artifact_object.object_id`
  - `target_type = 'object_node'`
  - `target_id = kb.object_nodes.object_id`
  - `relation_name = 'belong_to'`
  - `relation_method = 'object_id'`
  - `source_record_id = kb.artifact_objects.source_record_id`

## 3.2 Output

With the v6 source-only prompt, translated fields below remain empty unless the
source itself is English and native values are copied into existing English
fields server-side. Their definitions also cover legacy/enriched records.

### 3.2.1 Output Record

For each extracted provision, generate a unique Provision ID (`prov_id`) using the format `<record_id>_prv_<sequence_number>`, where the sequence number starts at 1 within the input record. The `prov_id` is relative to the input record, so uniqueness is:

```text
(input_record_id, prov_id)
```

Normalize each extracted provision to:

- `prov_id`: string in the format `<record_id>_prv_<sequence_number>`
- `prov_name`: normalized provision name
- `prov_name_en`: English translation of prov_name
- `provision`: original provision text
- `provision_en`: English provision text or translation
- `provision_subject`: provision subject
- `provision_subject_en`: English translation of provision_subject
- `prov_desc`: provision description or provision text
- `prov_desc_en`: English translation of prov_desc
- `prov_context`: surrounding context
- `prov_context_en`: English translation of prov_context
- `provision_keywords`: keywords for search
- `provision_keywords_en`: English keywords for search
- `category_paths`: category path payload from the LLM output
- `category_paths_en`: English category path payload (mapped from LLM field `category_path_en`)
- `location_type`: sentence, paragraph, bullet, table_row, table_cell, heading_context, or mixed
- `confidence`: confidence score
- `is_explicit`: whether the provision is explicit in the source
- `need_verify`: whether the provision should be verified by a human
- `status`: provision record status, default `active`
- `create_time`: creation time
- `modify_time`: last modification time
- `public_info`: additional public metadata, including source line spans
- `private_info`: additional private metadata
- `notes`: notes
- `error_msg`: error message, if any

### 3.2.2 Output Storage
- Upsert all provisions to 'kb.provisions'
- Save all provisions in 
`ARTIFACT_DIR + /<group_id>/<record_id>/<filename_root>_<parser_name>.provisions`
where:
  - `<group_id>` = floor(record_id / 1000)`
  - `<filename_root>` is the root of 'kb.inputs.staging_filename'
  - `<parser_name> is 'kb.inputs.parser_name'

`provisions.txt` file format:

```text
[
    {
      "prov_id":"173_prv_273",
      "prov_name": "<provision name>",
      "prov_name_en": "<provision name>",
      "prov_type": "mandatory",
      "provision": "<original provision text>",
      "provision_en": "<English translation or same as original if English>",
      "provision_desc": <the description about the provision>,
      "provision_desc_en": <the English translation of provision_desc>,
      "source_line_spans": ["497-498"],
      "context":"<the context>",
      "context_en":"<the English translation of the context if its input lanuage is not English>",
      "subject":"<the provision's subject>",
      "subject_en":"<the provision's subject>",
      "location_type":"<the location type>",
      "keywords": ["keyword", "keyword"...],
      "keywords_en": ["keyword", "keyword"...],
      "confidence": 0.0,
      "is_explicit": true or false,
      "need_verify": true or false,
    },
    ...
]
```

## 3.3 Implementations
### 3.3.1 Search And Artifact Connections

- The shared hybrid-search behavior is configured by `ChenWeb/config.toml` `[artifact_search]`.
- Provision-specific lexical emphasis is configured by `ChenWeb/config.toml` `[provisions_search_weights]`.
- In Phase B the extractor rebuilds the provision rows in `kb.search_artifacts` and writes the
  chunk→provision line-overlap `has-provision` connections.
- In Phase C (`ProvisionsProcessor.PostProcessIndex`) indexing rebuilds the registry rows,
  writes the `#shared_artifact` line-overlap artifact edges (§3.1.1), and writes category-path
  `provisions.txt` entries. Semantic provision↔provision similarity is **not** materialized —
  it is computed live at read time by the reviewer via `FindSimilarArtifactsOnTheFly` (there is
  no index-time hybrid artifact-connection step).

Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-impl.md

## 3.4 Benchmark
Output quality is measured against gold provisions: the `extract-provisions-benchmark` skill builds
them (`testbed.provisions`, versioned rules), `score-extract-provisions` scores `kb.provisions`
against them (1–100), and ChenWeb shows both under System Admin › Benchmark › Provisions
(development page). See devdoc
`KnowledgeStore/doc-repo/devdocs/202611/2026110602-devdoc-provisions-benchmark.md`.

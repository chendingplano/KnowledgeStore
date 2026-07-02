A semantic projection is a a compact, semantically rich representation optimized for retrieval, discoverability, clustering, and semantic matching.

Extract semantic projection is a doc processor (refer to [4]). It uses a multi-pass extraction strategy.

## Input

- `record_id`: the value of `kb.inputs.id`
- `chunks`: using the fix-size chunking (refer to [5])

## Implementation

Refer to [6] for its implementation.

## Multi-Pass Pipeline

Multi-pass pipeline breaks the processing into multiple passes:

1. Pass 1: extract semantic projection candidates from each chunk.
2. Pass 2: enrich each candidate into final semantic projection rows

### Pass 1: Extract Candidates

Pass 1 uses:

- model env: `EXTRACT_SEMANTIC_PROJECTION_MODEL_NAME`
- prompt env: `EXTRACT_SEMANTIC_PROJECTION_PROMPT`

Optional fallback:

- `EXTRACT_SEMANTIC_PROJECTION_MODEL_FALLBACK`

Pass 1 output:

```json
{
  "semantic_projection": "...",
  "keywords": ["..."]
}
```

### Pass 2

Pass 2 uses:

- model env priority:
  - `ENRICH_SEMANTIC_PROJECTION_MODEL_NAME`
- prompt env priority:
  - `ENRICH_SEMANTIC_PROJECTION_PROMPT`

Pass 2 output:

```json
{
  "language": "string",
  "descriptive_name": "string",
  "descriptive_name_en": "string",
  "keywords":["string"],
  "keywords_en":["string"],
  "category_paths": [
    {
      "category_path": [
        {"name": "string", "keywords": ["string"], "confidence": 0.0},
        {"name": "string", "keywords": ["string"], "confidence": 0.0}
      ],
      "path_keywords": ["string"],
      "path_confidence": 0.0
    }
  ],
  "category_paths_en": [
    {
      "category_path": [
        {"name": "string", "keywords": ["string"], "confidence": 0.0},
        {"name": "string", "keywords": ["string"], "confidence": 0.0}
      ],
      "path_keywords": ["string"],
      "path_confidence": 0.0
    }
  ]
}
```

### Logging

The processor should log:

- candidate-pass start
- raw parsed LLM payload/error
- enrichment-pass start
- enrichment results
- final results

The shared LLM client should also log the raw HTTP response body before decoding.

### Semantic Projection ID

Semantic projections are identified by:

```text
<record_id>_smp_<seqno>
```

where `<seqno>` is a global sequence number across all chunks, starts at `1`.

Assign a semantic projection ID to each semantic projection.

### Line Spans

Each semantic projection records the source lines it was derived from in a
`line_spans` field. Because there is a one-to-one mapping between a chunk and a
semantic projection, `line_spans` is taken from the source chunk's lines.

- **Format:** a JSON array of line-range strings, e.g. `["1-4", "9-12"]`. Each
  entry is either a single line number (`"7"`) or an inclusive range
  (`"start-end"`). Contiguous line numbers are collapsed into ranges; overlap
  (carry-over) lines are excluded.
- **Storage:** persisted to the `kb.semantic_projections.line_spans` JSONB
  column.

`line_spans` provides the line-level grounding for a projection — the spans that
tie it back to the source document.

## Workflow

- For each chunk, run Pass 1 to extract its semantic projection.
- Retry extraction with `EXTRACT_SEMANTIC_PROJECTION_MODEL_FALLBACK` when the primary candidate model fails.
- If both primary and fallback candidate extraction return the empty/truncated JSON failure shape, it is an error.
- For each semantic projection, run Pass 2 to enrich it into final semantic projection.
- Generate a semantic projection ID for each semantic projection and save it as `semantic_proj_id`
- Derive `line_spans` from the source chunk (see [Line Spans](#line-spans); one-to-one mapping between chunks and semantic projections) and save it as `line_spans`.
- Add a `create_time` to each semantic projection.
- Save final semantic projection to `kb.semantic_projections`.
- Write `.semantic_projections` artifact output.
- Index semantic projections.
- Upsert status in `kb.inputs.status`.

Failure status entry:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_semantic_projections",
  "proc_status": "failed",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "error": "error-msg",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

Success status entry:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_semantic_projections",
  "proc_status": "success",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

## Output Storage

### Save to Table `kb.semantic_projections`

Construct a row for each final semantic projection and insert it.

Rules:

- save the JetStream event ID to `event_id`
- save `line_spans` (the source chunk's line ranges; see [Line Spans](#line-spans)) to the `line_spans` JSONB column
- if the original language is English, do not generate/store the "_en" fields.
- save additional information to `ext_info`

### Save to File

Each semantic projection written to the file includes `line_spans` (see [Line Spans](#line-spans)).

Write all final semantic projections in JSON to:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.semantic_projections
```

where:

- `<group_id>` = `floor(record_id / 1000)`
- `<filename_root>` is derived from `kb.inputs.staging_filename`
- `<parser_name>` is `kb.inputs.parser_name`

## Index Semantic Projections

Indexing runs in the pipeline's **Phase C (post-process)** —
`SemanticProjectionsProcessor.PostProcessIndex` — after every doc processor for the record has
finished (it reads other processors' artifacts and their `kb.search_artifacts` rows).
`connected_artifacts` for a semantic projection is **computed on demand** by
`kb.connected_artifacts(record_id, 'semantic_projection', source_row_id)`; it is not
materialized. Semantic projections carry no `artifact_categories` keys, so there are no
`belong_to` category-membership edges (unlike metrics / inventory items / entities).

### Index Semantic by Category Paths
Refer to [1].

### Full-Text Search Index
Make sure semantic projections can be full-text searched, similar to [2] and [3].

### Line-Overlap Artifact Edges

In Phase C, after the semantic-projection rows are rebuilt in `kb.search_artifacts`
(`ReindexSemanticProjectionSearchForRecord`), indexing materializes intra-document,
line-overlapping artifacts as traversable edges in `kb.artifact_connections`, built
deterministically (no LLM or hybrid search). Reviewers start from a semantic projection and
reach the entities/metrics/etc. that share its lines (a read matches either endpoint).

For each semantic projection `SP` in the record being indexed:

1. Find every artifact in the **same document** whose line spans overlap `SP`'s, grouped by
   type `T ∈ {entity, metric, provision, inventory_item, topic}` (the self family,
   `semantic_projection`, is excluded). Overlap is computed by self-joining
   `kb.search_artifacts` on the GiST-indexed `line_range && line_range` operator, so both
   endpoints use their canonical `artifact_id`s.
2. For each overlapping artifact (anchor) `X` of type `T`, upsert one edge to
   `kb.artifact_connections`:
   - `source_type = T`, `source_id = X.artifact_id`, `source_record_id = record_id`
   - `target_type = 'semantic_projection'`, `target_id = SP.artifact_id`, `target_record_id = record_id`
   - `relation_name = '#shared_artifact'`
   - `relation_method = 'line-overlapped-artifact'`
   - `confidence = 1.0` (deterministic overlap)
   - `extra_info` containing at least `{"source":"extract_semantic_projections","anchor_type":T}`

The overlapping anchor is the **source** and the semantic projection is the **target**;
because both share lines, these edges are always intra-document (`source_record_id =
target_record_id = record_id`).

**Idempotency.** Rebuilt each run by `ReplaceSharedArtifactEdges`, which deletes the record's
existing edges scoped to `target_type = 'semantic_projection'` (plus
`relation_method = 'line-overlapped-artifact'`, `relation_name = '#shared_artifact'`), then
inserts the fresh set. The delete is scoped by target family so parallel Phase-C family runs
never clobber each other's edges.

## References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md \
[2] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[3] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-impl.md \
[4] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md \
[5] KnowledgeStore/Capsules/coding-capsules/chunking/+CAPSULE.md \
[6] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-semantic-projection-impl.md

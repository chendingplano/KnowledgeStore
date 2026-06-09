## Input

- record_id: the value of kb.inputs.id, identifies the record to process
- chunks

Each chunk line is formatted as:
```
<flag>\t<line_number>\t<page_number>\t<line_type>\t<content>
```

Where:
- `<flag>` is `n` for a normal line and `o` for an overlap line
- `<line_number>` is the line number within the source document
- `<page_number>` is the source page number
- `<line_type>` is the normalized line type
- `<content>` is the extracted line content

# Generate Scene Blocks Processor

This processor should use multiple LLM passes instead of a single overloaded prompt.

The old single-pass design asked one model call to do all of the following at once:

- identify scene boundaries
- deduplicate overlapping chunk results
- infer structured scene semantics
- generate bilingual fields
- generate discriminators and retrieval metadata

That caused the same class of issues seen in product extraction:

- unstable extraction counts across repeated runs
- duplicate scene blocks from overlapping chunks
- prompt/schema overload on smaller models
- malformed or partial JSON responses
- weak deterministic cleanup between chunk-level recall and final storage

## Multiple LLM Passes

The processor should split the work into the following stages:

1. Pass 1: extract lightweight scene candidates per chunk
2. Deterministic Step A: merge and deduplicate scene candidates across overlapping chunks
3. Pass 2: group merged candidates by primary chunk; enrich each group in a single LLM call
4. Deterministic Step B: final scene-block dedup before persistence

## Pass 1 Output: Scene Candidates

Pass 1 uses `EXTRACT_SCENE_CANDIDATES_MODEL_NAME` with `EXTRACT_SCENE_CANDIDATES_PROMPT`.

The LLM output format is:

```json
{
  "candidates": [
    {
      "scene_key": "stable_snake_case_identifier",
      "scene_type_hint": "workflow|operation|failure|decision|monitoring|compliance|state_transition|interaction|other",
      "title": "human readable title",
      "summary_hint": "one sentence description of the scene",
      "evidence_quote": "short exact quote from the input",
      "line_spans": ["12", "13-15"],
      "confidence": 0.0,
      "confidence_reason": "brief reason"
    }
  ]
}
```

This pass should:

- maximize recall for real scene-like situations
- avoid generating the full final schema
- avoid overlap-only candidates unless the same scene is supported by normal lines
- avoid translation and heavy metadata generation

## Deterministic Intermediate: Scene Candidates

After all chunks are processed:

- remove overlap-only candidates unless normal-line support exists
- normalize scene keys and titles for grouping
- merge duplicate candidates across overlapping and adjacent chunks
- preserve provenance such as evidence quotes, line spans, and supporting lines

## Pass 2 Output: Final Scene Blocks

Pass 2 uses `ENRICH_SCENE_BLOCKS_MODEL_NAME` with `ENRICH_SCENE_BLOCKS_PROMPT`.

The LLM output format is:
```json
{
  "scene_blocks": [
    {
      "scene_id": "stable_snake_case_identifier",
      "scene_type": "string",
      "title": "human readable title",
      "title_en": "human readable title",
      "line_spans": ["12", "13-15"],
      "summary": "standalone description of the semantic situation",
      "summary_en": "standalone description of the semantic situation",
      "actors": [
        {
          "type": "human|system|organization|service|device|agent|role",
          "name": "string",
          "name_en": "string"
        }
      ],
      "resources": [
        {
          "type": "document|system|database|file|equipment|tool|record|artifact|resource",
          "name": "string",
          "name_en": "string"
        }
      ],
      "preconditions": ["string"],
      "preconditions_en": ["string"],
      "triggers": ["string"],
      "triggers_en": ["string"],
      "states": ["string"],
      "states_en": ["string"],
      "actions": [
        {
          "sequence": 1,
          "actor": "string",
          "action": "string"
        }
      ],
      "actions_en": [
        {
          "sequence": 1,
          "actor": "string",
          "action": "string"
        }
      ],
      "constraints": ["string"],
      "constraints_en": ["string"],
      "decisions": ["string"],
      "decisions_en": ["string"],
      "outcomes": ["string"],
      "outcomes_en": ["string"],
      "failure_modes": ["string"],
      "failure_modes_en": ["string"],
      "root_causes": ["string"],
      "root_causes_en": ["string"],
      "resolutions": ["string"],
      "resolutions_en": ["string"],
      "relationships": [
        {
          "type": "depends_on|causes|triggers|constrains|uses|applies_to|references|produces",
          "target": "semantic target"
        }
      ],
      "relationships_en": [
        {
          "type": "depends_on|causes|triggers|constrains|uses|applies_to|references|produces",
          "target": "semantic target"
        }
      ],
      "discriminators": [],
      "keywords": ["normalized_keyword"],
      "keywords_en": ["normalized_keyword"],
      "confidence": 0.0,
      "line_spans": ["12", "18-20"]
    }
  ]
}
```

## Scene Block ID
Scene blocks are identified by Scene Block IDs: `<record_id>_sbk_<seqno>`, where `<seqno>` is a sequence number 
relative to the record, starting at 1. Examples:
```
201_sbk_1
201_sbk_2
...
```

Assign a scene object ID for each of the scene object generated.

## Concurrency

Both LLM passes support bounded parallelism controlled by `GENERATE_SCENE_BLOCKS_MAX_TASKS`:

- Pass 1 chunks may be processed concurrently up to `GENERATE_SCENE_BLOCKS_MAX_TASKS` at a time.
- Pass 2 chunk groups may be processed concurrently up to `GENERATE_SCENE_BLOCKS_MAX_TASKS` at a time.
- The deterministic merge step (between Pass 1 and Pass 2) always runs after all Pass 1 jobs complete; Pass 2 does not start until the merge is done.
- Result ordering is deterministic regardless of completion order: Pass 1 results are flattened in chunk index order; Pass 2 results are flattened in chunk group order.
- The default value of `GENERATE_SCENE_BLOCKS_MAX_TASKS` is `1` (sequential), preserving the original behavior when the variable is unset.

## Workflow
- The input to this processor is chunks
- Run Pass 1 on all chunks concurrently (up to `GENERATE_SCENE_BLOCKS_MAX_TASKS`) to extract scene candidates.
- After all Pass 1 jobs complete, run deterministic candidate merge and overlap cleanup.
- Group merged candidates by primary chunk (the chunk where each candidate was first seen).
- Run Pass 2 on all chunk groups concurrently (up to `GENERATE_SCENE_BLOCKS_MAX_TASKS`) to enrich each group into final scene blocks.
- Run final scene-block dedup before persistence.
- After processed all the chunks, save the extracted scene blocks to kb.scene_blocks (refer to "Output Storage" section).
- Upsert the following entry to kb.input.status if faled:

```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "generate_scene_blocks",
    "proc_status":"failed",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "error":"error-msg",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
    "model_name":"gpt-5.4-mini",
    "prompt_name":"the-prompt-file-name"
}
```

Otherwise, upsert the following element to kb.inputs.status:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "extract_scene_blocks",
    "proc_status":"success",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
    "model_name":"gpt-5.4-mini",
    "prompt_name":"the-prompt-file-name"
}
```

## Index Scenes
Refer to 'KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md'

### Output Storage

Add "create_time" to each of the scene blocks.

#### Save to Table `kb.scene_objects`
Construct a record of 'kb.scene_objects' for each scene block and upsert the record to the table. 
When constructing the record, follow the following rules:
* Save the JetSteram event ID to 'event_id'
* Save additional information to 'ext_info'

#### Save to File
It saves all the scene blocks into a '.scene_blocks' file. The file name is: 'ARTIFACT_DIR + /<group_id>/<record_id>/<filename_root>_<parser_name>.scene_blocks',
where:
- '<group_id>' = floor(record_id / 1000)
- '<filename_root>' is the root of 'kb.inputs.staging_filename'
- '<parser_name>' is 'kb.inputs.parser_name'

## Implementation
Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-scene-blocks-impl.md
for its implementations.

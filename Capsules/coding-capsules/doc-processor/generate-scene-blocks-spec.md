## Input

- record_id: the value of kb.inputs.id, identifies the record to process
- chunks

## LLM Output Format
It uses EXTRACT_SCENE_BLOCKS_MODEL_NAME with the EXTRACT_SCENE_BLOCKS_PROMPT prompt
to extract scene blocks. The LLM output format is:
```json
{
  "scene_blocks": [
    {
      "scene_id": "stable_snake_case_identifier",
      "scene_type": "string",
      "title": "human readable title",

      "summary": "standalone description of the semantic situation",

      "actors": [
        {
          "type": "human|system|organization|service|device|agent|role",
          "name": "string"
        }
      ],

      "resources": [
        {
          "type": "document|system|database|file|equipment|tool|record|artifact|resource",
          "name": "string"
        }
      ],

      "preconditions": [
        "conditions that must already be true"
      ],

      "triggers": [
        "events that activate this scene"
      ],

      "states": [
        "important states during this scene"
      ],

      "actions": [
        {
          "sequence": 1,
          "actor": "string",
          "action": "string"
        }
      ],

      "constraints": [
        "rules, thresholds, deadlines, obligations"
      ],

      "decisions": [
        "branching decision logic if applicable"
      ],

      "outcomes": [
        "expected results"
      ],

      "failure_modes": [
        "what can go wrong"
      ],

      "root_causes": [
        "if causal failure analysis is present"
      ],

      "resolutions": [
        "corrective actions if applicable"
      ],

      "relationships": [
        {
          "type": "depends_on|causes|triggers|constrains|uses|applies_to|references|produces",
          "target": "semantic target"
        }
      ],

      "discriminators": [
        {
          "intent": "short interpretation of user need",
          "domain": ["domain1", "domain2"],
          "discriminators": [
            {
              "category": "lexical | synonym | abbreviation | metadata | structural | graph | heuristic",
              "value": "string",
              "confidence": 0.0,
              "reason": "why this helps discriminate"
          }
          ],
          "exploration_plan": [
            "ordered recommended exploration steps"
          ]
        },
      ],

      "keywords": [
        "normalized_keyword"
      ],

      "confidence": 0.95,

      "source_refs": [
        {
          "source_id": "string",
          "evidence_type": "raw_text|summary|provision|topic|execution_trace|conversation",
          "reference": "location reference"
        }
      ]
    }
  ]
}
```

## Scene Block ID
Scene blocks are identified by Scene Block IDs: `<record_id>_<seqno>`, where `<seqno>` is a sequence number 
relative to the record, starting at 1. Examples:
```
201_1
201_2
...
```

Assign a scene object ID for each of the scene object generated.

## Workflow
- The input to this processor is chunks
- For each chunk, it uses the model EXTRACT_SCENE_BLOCKS_MODEL_NAME with the EXTRACT_SCENE_BLOCKS_PROMPT prompt
  to extract scene blocks from the chunk.
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

### Output Storage

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

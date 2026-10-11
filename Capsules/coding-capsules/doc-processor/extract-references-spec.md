# extract_references — spec

The lower reference layer of the doc processor. It finds every reference a document makes,
labels it with the reference model, catalogues the referenced resources, and resolves each reference
to the user's own copy of the target. Artifact extractors (first: `extract_metrics`) then resolve the
references that concern their own artifacts.

**The contract is in OpenSpec**, not here:
`ChenWeb/openspec/changes/extract-references-processor/specs/` (capabilities `document-references`,
`reference-artifact-resolution`, `metric-reference-resolution`) and `design.md` (decisions D1–D14).
If behaviour changes, change those specs. This page only orients a reader inside the capsule.

Design intent and the reference model: devdoc
`KnowledgeStore/doc-repo/devdocs/202610/2026101002-devdoc-extract-references-processor.md`.

## Place in the pipeline

| Item | Value |
|---|---|
| Name | `extract_references` |
| Type / stage | configurable, Phase B (`ChunkBatchProcessor`) |
| Depends on | `chunking` only: it reads no output of any other extractor |
| Input | the shared chunk set via `canonicalChunkInputText` (shares the DeepSeek cached prefix) |
| Prompt | `prompts/prompt-extract-references-v1.md` (env `EXTRACT_REFERENCES_PROMPT`) |
| Model | env `EXTRACT_REFERENCES_MODEL_NAME` (via `MODEL_DEF_FILE`); `MODEL_DEFAULT_REASONING_POLICY=no-reasoning` forces thinking off |
| Output | `kb.ref_mentions`, `kb.ref_resources`, `kb.ref_resource_versions`, `kb.ref_resource_identifiers`; through resolvers `kb.reference_artifact_links` and resolved rows `<rec>_rfm_<n>` in `kb.metrics` |

## What one run does (`FinalizeChunkBatch`)

1. Assemble the chunks' references:
   - de-duplicate overlapping chunks (one listed entry per list line; an in-text reference is
     identified by what it cites);
   - normalize labels to the governed vocabularies;
   - parse identifiers in code;
   - derive normativity from the formal lists.
2. Replace the record's mentions and upsert the catalog (R1). Deleting the old mentions cascades
   their links and resolved rows away.
3. Attach the document to its own resource through a `kb_input` identifier (never public).
4. Holding resolution (R2) for the record's mentions, under the access rule (same user, same store,
   or an active grant).
5. Step 5: `ResolveOutgoing`, i.e. every registered family resolver for the record's references.
6. Holding event: other records' mentions of this document's resource become `held`, and every
   family with artifacts here runs `ResolveIncoming`.

Resolution failures are logged at WARN and never fail the run.

## Artifact families

| Family | Resolver | Takes | Step 6 caller |
|---|---|---|---|
| metric | `reference_metric_resolver.go` | `target_content` = `criterion` / `criteria_set` | `extract_metrics` after saving (`resolveIncomingReferences`) |

Provisions, entities and inventory items have no resolver yet.

## Rules every `kb.metrics` reader follows

Resolved rows (`ref_mention_id` set) carry another document's value. Every query reading `kb.metrics`
excludes them (`ref_mention_id IS NULL`), except the metric list API, which returns them with their
`ref_*` fields. `TestKBMetricsReadersExcludeResolvedRows` enforces this. `extract_metrics` never
deletes or merges them.

## Status entry

Written by the chunk batch coordinator like every chunk processor:

```json
{
  "operation": "extract_references",
  "proc_status": "success | failed | active | stopped",
  "start_time": "yyyymmdd hh:mm:ss"
}
```

Counts per normativity, target type, content and resolution outcome are in the
`extract references saved` log line.

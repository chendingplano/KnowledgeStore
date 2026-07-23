# ADR: Deleting `kb.inputs` Records and Generated Artifacts

**Date:** 2026-07-23 \
**Status:** Accepted \
**Component:** ChenWeb Knowledge Base / Doc Processor \
**Authors:** Chen Ding

## Change Logs

* 2026/07/23, ADR created. Defines the deletion model for `kb.inputs`,
  documents current generated data, and establishes the future deleter
  registration contract for doc processors and other artifact-producing modules.

## Context

`kb.inputs` is the root record for a document imported into the knowledge base.
After upload and parsing, the doc processor pipeline may generate database rows,
files under `ARTIFACT_DIR`, and category-path index files under
`ARTIFACT_WEB_DIR`.

Before this ADR, deleting a row from the import page only removed the
`kb.inputs` row. That left processor output behind: extracted metrics,
provisions, entities, semantic projections, review records, search registry
rows, and file-based artifacts. The result was stale data appearing in search,
wiki/category pages, and review views even after the source document had been
deleted.

The delete operation must therefore mean "delete the input document and all
document-owned artifacts derived from it", not merely "delete one row from
`kb.inputs`".

## Decision

Deleting a `kb.inputs` record is a document lifecycle operation.

The delete flow SHALL:

1. Identify the input record and collect its file paths before deleting the row.
2. Delete document-owned database rows in a transaction.
3. Delete the `kb.inputs` row in the same transaction.
4. Commit the database transaction.
5. Delete document-owned files and artifact directories after commit.
6. Log file cleanup failures as warnings unless they make the database delete
   unsafe.

Database cleanup is transactional because partial table cleanup creates
hard-to-debug stale state. File cleanup is best effort after commit because file
systems cannot participate in the PostgreSQL transaction. A committed database
delete must not be rolled back merely because a stale file cannot be removed.

The initial implementation lives in:

* `ChenWeb/server/api/kbhandler/metrics_handler.go::DeleteInput`

The current implementation is intentionally centralized for the existing
artifact families, but that is not the desired long-term shape. Future artifact
producers SHALL register a focused deleter so ownership remains local to the
module that creates the artifacts.

## Source of Truth: What a `kb.inputs` Record May Generate

This section is the source of truth for deletion ownership. Any new doc
processor, review module, indexer, search module, or related subsystem that
generates data owned by a `kb.inputs.id` MUST update this section and register
its deleter.

### Source Input Data

Upload and parsing may populate these fields on `kb.inputs`:

* `file_name`: usually the uploaded source file path.
* `backup_filename`: backup copy, when configured.
* `result_filename`: parser output path or derived artifact path.
* `status`, `parse_state`, `pipeline_state`, `doc_metadata`, and related
  rollup columns.

Delete behavior:

* Delete the `kb.inputs` row.
* Remove `file_name`, `backup_filename`, and `result_filename` file paths when
  non-empty.
* Resolve relative paths using the same path rules used by read endpoints:
  `file_name` and `result_filename` use `DATA_HOME_DIR`; `backup_filename`
  uses `DATA_BACKUP_DIR` rules.

### Processor Tables

Doc processors may generate rows scoped by `input_record_id`:

* `kb.metrics`
* `kb.provisions`
* `kb.products`
* `kb.scene_objects`
* `kb.semantic_projections`
* `kb.knowledges`
* `kb.entities`
* `kb.relations`
* `kb.inventory_items`
* `kb.inventory_item_duplicates`
* `kb.summaries`
* `kb.topics`

Delete behavior:

* Delete all rows where `input_record_id = kb.inputs.id`.
* If a processor stores child rows that reference these rows without
  `ON DELETE CASCADE`, delete the child rows first.
* If a processor uses stable artifact IDs such as `415_metric_001` or
  `415_semproj_003`, do not rely only on the ID prefix; `input_record_id` is
  the primary ownership key.

### Pipeline Status, Runs, and Logs

Pipeline execution may generate:

* `kb.input_proc_status`, keyed by `record_id`.
* `kb.doc_process_runs`, keyed by `record_id`.
* `kb.doc_proc_logs`, keyed by `record_id`, and sometimes linked to
  `kb.doc_process_runs.id`.

Delete behavior:

* Delete log rows before deleting their run rows when FK constraints require it.
* Delete rows where `record_id = kb.inputs.id`.
* Pipeline logs are document-owned operational records. They should disappear
  with the input unless explicitly copied to a separate audit system.

### Search and Graph Indexes

Indexing may generate:

* `kb.search_artifacts`, keyed by `input_record_id`.
* `kb.chunk_ranges`, keyed by `input_record_id`.
* `kb.artifact_connections`, keyed by `input_record_id`; newer schema variants
  may also include `source_record_id` and `target_record_id`.
* `kb.artifact_objects`, keyed by `input_record_id` and
  `source_record_id`.

Delete behavior:

* Delete all rows where `input_record_id = kb.inputs.id`.
* For connection tables that carry `source_record_id` or `target_record_id`,
  remove edges where either endpoint belongs to the deleted input.
* `kb.artifact_objects` currently has `ON DELETE CASCADE` from `kb.inputs`,
  but deleters should not assume every future index table will have cascade
  constraints.
* Do not delete shared dictionaries, category registries, object nodes, or
  relation predicate catalogs only because one input is deleted. Those tables
  are corpus-level state unless a future ADR reclassifies them.

### Document Review Data

On-demand document review may generate:

* `kb.doc_review_requests`
* `kb.doc_review_runs`
* `kb.doc_review_findings`
* `kb.doc_review_reports`
* `kb.doc_review_status`
* `kb.doc_review_activities`
* `kb.doc_review_logs`
* `kb.doc_review_provision_analyses`

Delete behavior:

* Delete rows where `input_record_id = kb.inputs.id`.
* Delete run-scoped children before deleting `kb.doc_review_runs`.
* Delete request rows after run/report/status/finding/log rows.
* Review rows are document-owned unless explicitly exported into a separate
  immutable report archive.

### File Artifacts Under `ARTIFACT_DIR`

Doc processors store per-record files under a group directory based on
`recordID / 1000`. For example, record `415` may generate:

```text
$ARTIFACT_DIR/Artifacts/0/415/diaryMac_mineru.semantic_projections
```

Depending on deployment/configuration, the same logical record directory may
also appear without the extra `Artifacts` path component:

```text
$ARTIFACT_DIR/0/415/
```

Delete behavior:

* Delete the per-record artifact directory:
  `$ARTIFACT_DIR/Artifacts/<recordID/1000>/<recordID>/`.
* Also delete `$ARTIFACT_DIR/<recordID/1000>/<recordID>/` when that is the
  active layout.
* If `kb.inputs.result_filename` points into a per-record artifact directory,
  delete that directory as well.
* Do not delete parent group directories such as `$ARTIFACT_DIR/Artifacts/0`
  unless a separate cleanup task proves they are empty and safe to remove.

### Category-Path Files Under `ARTIFACT_WEB_DIR`

`ARTIFACT_WEB_DIR` contains category-path directories used by search/wiki
views. The leaf directories are shared across records that land in the same
category. They may contain:

* `metadata.txt`: category metadata.
* `semantic_projections.txt`: semantic projection IDs, usually prefixed by the
  input record ID, e.g. `415_...`.
* `chunks.txt`
* `entities.txt`
* `inventory_items.txt`
* `summaries.txt`
* `topics.txt`
* `metrics.txt`
* `provisions.txt`
* `products.txt`
* `relations.txt`
* `scenes.txt`

Semantic projection artifacts are special because the `.semantic_projections`
JSON file contains `category_paths` arrays; each path maps to a directory under
`ARTIFACT_WEB_DIR`. The category path controls which directories are relevant,
but the deleter must not depend on `connected_artifacts` inside the semantic
projection artifact. `connected_artifacts` is a derived/live view and should not
be written to `.semantic_projections` artifact JSON going forward.

For record `415`, the deleter must remove entries whose first field starts with
`415_` from every known per-leaf artifact index file listed above. This broad
prefix cleanup is required even when `$ARTIFACT_DIR/Artifacts/0/415` has already
been deleted and the `.semantic_projections` JSON is no longer available.

Delete behavior:

* Remove this record's entries from every known ArtifactWeb leaf index file,
  including but not limited to `semantic_projections.txt`, `metrics.txt`,
  `topics.txt`, `scenes.txt`, `inventory_items.txt`, `provisions.txt`,
  `summaries.txt`, and `entities.txt`.
* Remove the file if no entries remain.
* Prune directories that become empty or metadata-only after the record entries
  are removed.
* Do not blindly delete category-path directories that still contain artifact
  index files for other records.
* For other per-leaf index files, remove entries owned by the record according
  to that file's format. For example, topic entries carry `record_id`; semantic
  projection entries use the `recordID_` prefix.

## Future-Proof Deleter Registration Model

The long-term delete module should not be a single giant list of tables and
files. Each module that creates document-owned artifacts should register a
deleter. The delete coordinator should orchestrate these deleters.

Proposed interface:

```go
type InputArtifactDeleter interface {
    Name() string
    PlanDelete(ctx context.Context, input InputDeleteTarget) (InputDeletePlan, error)
    DeleteDB(ctx context.Context, tx *sql.Tx, plan InputDeletePlan) error
    DeleteFiles(ctx context.Context, plan InputDeletePlan, logger ApiTypes.JimoLogger) error
}
```

Suggested supporting types:

```go
type InputDeleteTarget struct {
    RecordID       int64
    FileName       string
    BackupFileName string
    ResultFileName string
}

type InputDeletePlan struct {
    RecordID int64
    Module   string
    Files    []string
    Dirs     []string
    Notes    []string
}
```

Coordinator behavior:

1. Load the `kb.inputs` row and build `InputDeleteTarget`.
2. Ask every registered deleter for a plan.
3. Begin a transaction.
4. Run each deleter's `DeleteDB`.
5. Delete the `kb.inputs` row.
6. Commit.
7. Run each deleter's `DeleteFiles`.
8. Return success with warnings if only file cleanup failed.

Registration rules:

* A module MUST register a deleter before it writes document-owned artifacts.
* The deleter MUST be owned by the module that writes the artifacts.
* The deleter MUST be idempotent.
* The deleter MUST tolerate missing rows and missing files.
* The deleter MUST document any shared state it intentionally leaves behind.
* The deleter SHOULD expose a dry-run plan for admin tooling.
* The deleter SHOULD include focused tests that prove rows/files for one input
  are deleted while rows/files for another input remain.

Example module ownership:

* `extract_semantic_projections`: deletes `kb.semantic_projections`,
  `.semantic_projections` files, and semantic projection entries under
  `ARTIFACT_WEB_DIR`.
* `extract_metrics`: deletes `kb.metrics`, metric search rows, metric category
  tree entries, and metric-related graph edges.
* `review_document`: deletes doc-review requests, runs, findings, reports,
  status, logs, activities, and provision analysis side rows.
* `search_indexing`: deletes `kb.search_artifacts`, `kb.chunk_ranges`, and
  search/graph indexes it owns.

## Edge Cases and Operational Rules

Missing files:

* Missing files are not errors. Delete operations should be idempotent.

Partially completed pipelines:

* A document may have only parser output, only mandatory processor output, or a
  partial set of configurable processor outputs. Every deleter must handle
  partial state.

Running pipelines:

* Deleting an input while a parser, converter, processor, or reviewer is still
  running can recreate artifacts after deletion. The UI or API should stop or
  reject active work before deletion when possible. As a defensive measure,
  workers must treat a missing `kb.inputs` row as terminal and avoid writing
  new artifacts for it.

Cross-document graph edges:

* Edges involving the deleted record must be removed even when the other
  endpoint belongs to another record.
* Shared canonical objects and category dictionaries should remain unless they
  are explicitly scoped to the deleted record.

Shared category paths:

* `ARTIFACT_WEB_DIR` category directories are shared. A deleter should remove
  this record's entries from index files, then prune directories only if they
  contain no remaining artifact index data.

Database/file ordering:

* Database cleanup happens before file cleanup.
* File cleanup should use plans captured before deleting the `kb.inputs` row.
* A failed file delete should be logged for follow-up but should not resurrect
  the deleted database row.

Schema evolution:

* New artifact tables should include `input_record_id` or `record_id` and an
  index on that column.
* Prefer FK constraints with `ON DELETE CASCADE` for strictly child tables, but
  still register a deleter so file artifacts and non-FK state are covered.

Audit requirements:

* If compliance requires retaining delete history, write a separate audit event
  before commit. Do not keep normal processor output as the audit log.

## Consequences

Deleting a document becomes safer and more complete: user-facing search,
category, wiki, and review views should not surface artifacts from deleted
inputs.

The immediate cost is that the current delete handler knows about many
existing artifact families. The future deleter registry is the migration path
away from that growing central list.

Every future artifact-producing module now has an explicit lifecycle
obligation: create artifacts, reprocess artifacts, and delete artifacts all
belong to the same feature design.

## Verification

Initial implementation verification:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/kbhandler -run 'TestDeleteInput|TestUpdate|TestListMetricsSortsByFirstSourceLineSpan|TestPruneMetadataOnlyArtifactWebDirs'
```

The delete module should eventually gain a broader integration test that seeds
a synthetic `kb.inputs` record with representative processor rows and
filesystem artifacts, runs the delete coordinator, and verifies that only data
owned by that record is removed.

## Documentation Impact

This ADR is the source of truth for `kb.inputs` artifact deletion.

Required follow-up documentation:

* Update `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
  to reference this ADR from the artifact storage and processor lifecycle
  sections.
* When adding a new processor, update both the processor capsule and this ADR's
  generated-data inventory.

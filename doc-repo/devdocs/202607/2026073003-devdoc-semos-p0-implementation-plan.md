# SemOS P0 Ontology Baseline Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record the verified SemOS P0 ontology baseline in the authoritative ADR, freeze the
competency-question and terminology contracts, and update the session handoff without changing
application code or database state.

**Architecture:** Keep ADR `2026072901` as the single architectural source of truth. Add verified
current-state evidence and competency contracts inside its P0 section, place the terminology
implementation crosswalk beside DR13, and make the handoff accurately distinguish completed P0
documentation from unstarted ontology runtime phases. PostgreSQL observations remain explicitly
point-in-time; schema and code behaviors become normative only where the ADR says so.

**Tech Stack:** Markdown, PostgreSQL catalog/read-only SQL, Go source inspection, `rg`, `git
diff --check`, Jujutsu (`jj`)

**Approved design:** `doc-repo/specs/202607/2026073004-spec-semos-p0-completion.md`

---

## Chunk 1: Verified P0 baseline

### Task 1: Refresh and record the deployed-system audit

**Files:**

- Modify: `doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`
- Reference: `doc-repo/specs/202607/2026073004-spec-semos-p0-completion.md`
- Reference code: `../ChenWeb/server/api/doc-processing/artifact_objects.go`
- Reference code: `../ChenWeb/server/api/kbsearch/registry.go`
- Reference code: `../ChenWeb/server/api/doc-processing/connections_store.go`
- Reference code: `../ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go`
- Reference code: `../ChenWeb/server/api/kbhandler/metrics_handler.go`

- [ ] **Step 1: Confirm both repositories are clean**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
jj status
cd /Users/cding/Workspace/ChenWeb
jj status
```

Expected: both commands report `The working copy has no changes.` Stop if either repository is
dirty.

- [ ] **Step 2: Refresh the schema, partition, constraint, and live-invariant evidence**

Run from `/Users/cding/Workspace/ChenWeb`:

```bash
set -a
source .env 2>/dev/null
set +a
PGPASSWORD="$PG_PASSWORD" psql -X -v ON_ERROR_STOP=1 \
  -U "$PG_USER_NAME" -d "$PG_DB_NAME" <<'SQL'
BEGIN READ ONLY;
\pset pager off

SELECT c.oid::regclass AS table_name,
       pg_get_partkeydef(c.oid) AS partition_key
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'kb'
  AND c.relname IN (
    'artifact_objects',
    'object_nodes',
    'search_artifacts',
    'artifact_connections',
    'scene_objects'
  )
ORDER BY c.relname;

SELECT parent.relname AS parent,
       child.relname AS partition,
       pg_get_expr(child.relpartbound, child.oid) AS bound
FROM pg_inherits i
JOIN pg_class parent ON parent.oid = i.inhparent
JOIN pg_class child ON child.oid = i.inhrelid
JOIN pg_namespace n ON n.oid = parent.relnamespace
WHERE n.nspname = 'kb'
  AND parent.relname IN ('search_artifacts', 'artifact_connections')
ORDER BY parent.relname, child.relname;

SELECT format(
  'SELECT %L AS parent, %L AS partition, count(*) AS exact_rows FROM %s;',
  parent.relname,
  child.relname,
  child.oid::regclass
)
FROM pg_inherits i
JOIN pg_class parent ON parent.oid = i.inhparent
JOIN pg_class child ON child.oid = i.inhrelid
JOIN pg_namespace n ON n.oid = parent.relnamespace
WHERE n.nspname = 'kb'
  AND parent.relname IN ('search_artifacts', 'artifact_connections')
ORDER BY parent.relname, child.relname
\gexec

SELECT conrelid::regclass AS table_name,
       conname,
       contype,
       pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid IN (
  'kb.artifact_objects'::regclass,
  'kb.object_nodes'::regclass,
  'kb.search_artifacts'::regclass,
  'kb.artifact_connections'::regclass,
  'kb.scene_objects'::regclass,
  'kb.inputs'::regclass
)
ORDER BY conrelid::regclass::text, contype, conname;

SELECT 'artifact_objects_rows' AS metric, count(*)::text AS value
FROM kb.artifact_objects
UNION ALL
SELECT 'artifact_objects_distinct_source_type_id',
       count(DISTINCT (source_record_id, artifact_type, artifact_id))::text
FROM kb.artifact_objects
UNION ALL
SELECT 'artifact_objects_duplicate_source_type_id_groups', count(*)::text
FROM (
  SELECT 1
  FROM kb.artifact_objects
  GROUP BY source_record_id, artifact_type, artifact_id
  HAVING count(*) > 1
) duplicate_groups
UNION ALL
SELECT 'artifact_objects_null_object_id', count(*)::text
FROM kb.artifact_objects
WHERE object_id IS NULL
UNION ALL
SELECT 'artifact_objects_orphan_object_id', count(*)::text
FROM kb.artifact_objects ao
LEFT JOIN kb.object_nodes object_node USING (object_id)
WHERE ao.object_id IS NOT NULL
  AND object_node.object_id IS NULL
UNION ALL
SELECT 'search_artifacts_rows', count(*)::text
FROM kb.search_artifacts
UNION ALL
SELECT 'artifact_connections_rows', count(*)::text
FROM kb.artifact_connections
UNION ALL
SELECT 'scene_objects_rows', count(*)::text
FROM kb.scene_objects;

SELECT 'search_artifacts.artifact_type' AS dimension,
       artifact_type AS value,
       count(*) AS rows
FROM kb.search_artifacts
GROUP BY artifact_type
ORDER BY count(*) DESC;

SELECT 'artifact_connections.relation_method' AS dimension,
       relation_method AS value,
       count(*) AS rows
FROM kb.artifact_connections
GROUP BY relation_method
ORDER BY count(*) DESC;

SELECT object_id, scene_id, input_record_id
FROM kb.scene_objects
ORDER BY id
LIMIT 12;

ROLLBACK;
SQL
```

Expected:

- `search_artifacts` is list-partitioned by `artifact_type`;
- `artifact_connections` is list-partitioned by `relation_method`;
- every search/connection partition has an explicit exact row count, including zero-row
  partitions;
- `artifact_objects` permits several rows for one
  `(source_record_id, artifact_type, artifact_id)`;
- `artifact_objects.object_id` has no FK to `object_nodes.object_id`;
- scene `object_id` values have the `<record>_sbk_<sequence>` occurrence form;
- all statements finish under `BEGIN READ ONLY` and end with `ROLLBACK`.

Record the fresh row counts as an explicitly dated observation, not an invariant.

- [ ] **Step 3: Refresh the knowledge-store inventory**

Run in the same read-only `psql` setup:

```sql
BEGIN READ ONLY;

SELECT ks.id,
       ks.ks_name,
       COALESCE(ks.ks_type, '') AS ks_type,
       COALESCE(ks.status, '') AS status,
       count(i.id) AS inputs
FROM kb.knowledge_store ks
LEFT JOIN kb.inputs i ON i.ks_store_id = ks.id
GROUP BY ks.id, ks.ks_name, ks.ks_type, ks.status
ORDER BY ks.id;

SELECT COALESCE(ks.ks_name, '<unassigned>') AS store,
       sa.artifact_type,
       count(*) AS artifacts,
       count(DISTINCT sa.input_record_id) AS documents
FROM kb.search_artifacts sa
JOIN kb.inputs i ON i.id = sa.input_record_id
LEFT JOIN kb.knowledge_store ks ON ks.id = i.ks_store_id
GROUP BY COALESCE(ks.ks_name, '<unassigned>'), sa.artifact_type
ORDER BY store, artifacts DESC;

SELECT count(*) AS unassigned_inputs
FROM kb.inputs
WHERE ks_store_id IS NULL;

ROLLBACK;
```

Expected: `Research` is populated, `卫健委标准` exists but is empty, and at least the current
unassigned-input count is reported. If deployed data differs, document the fresh result rather
than preserving an old count.

- [ ] **Step 4: Verify code-path lifecycle behavior**

Run:

```bash
cd /Users/cding/Workspace/ChenWeb
rg -n \
  "ReplaceObjectsForRecord|DELETE FROM kb\\.artifact_objects|source_record_id = \\$1 AND artifact_type" \
  server/api/doc-processing/artifact_objects.go
rg -n \
  "DeleteSearchRegistryRowsForRecord|InsertSearchRegistryRows|replaceRegistryRows" \
  server/api/kbsearch/registry.go server/api/doc-processing/search_indexing.go
rg -n \
  "ReplaceConnections|BeginTx|DELETE FROM kb\\.artifact_connections|ON CONFLICT" \
  server/api/doc-processing/connections_store.go
rg -n \
  "DeleteSceneObjectsByInputRecordID|objectID := fmt\\.Sprintf|ON CONFLICT \\(input_record_id, object_id\\)" \
  server/api/doc-processing/generate-scene-blocks-processor.go
rg -n \
  "inputRelatedDeleteSpecs|kb\\.object_nodes|kb\\.artifact_objects|kb\\.search_artifacts" \
  server/api/kbhandler/metrics_handler.go server/api/kbhandler/metrics_handler_test.go

rg -n \
  "ADD COLUMN IF NOT EXISTS ks_store_id|ks_store_id|knowledge_store" \
  project_migrations/20260425000002_add_kb_inputs_store_fields.sql \
  server/api/cdmhandler/documents.go \
  server/api/kbhandler/upload_handler.go \
  server/api/kbhandler/stores_handler.go \
  server/api/kbhandler/default_store_handler.go

rg -n -A12 -B2 \
  "required_processors" \
  config.toml \
  server/api/doc-processing/runtime.go \
  server/api/doc-processing/runtime_selection_test.go \
  server/api/kbhandler/kb_config_handler.go
```

Expected evidence:

- artifact-object replacement is transactional and scoped by record plus artifact family;
- search-registry replacement performs delete and insert as separate DB calls;
- connection replacement is transactional and scoped by method/name or method/source;
- forced scene reprocessing deletes existing scenes before extraction;
- input deletion removes per-record artifacts while intentionally retaining corpus-wide
  `object_nodes`.
- migration `20260425000002` added nullable `ks_store_id` without a knowledge-store FK;
- CDM/upload ingestion paths can persist `ks_store_id`;
- store CRUD and default-store resolution exist;
- runtime selection still reads one global `doc-processing.required_processors` list and does not
  select a pipeline from knowledge-store membership.

In the ADR evidence list, cite each of the migration and Go/config paths above beside the C5 or
routing claim it supports.

- [ ] **Step 5: Correct ADR C5**

Replace the heading `Knowledge stores exist as a registry but are not wired to anything` with
`Knowledge stores have partial membership wiring but no semantic or pipeline role`.

Replace the paragraph with a concise statement containing all of these facts:

- `kb.knowledge_store` has CRUD and default-store resolution;
- `kb.inputs.ks_store_id` already exists and ingestion paths can populate it;
- the deployed column is nullable, has no FK, and uses the legacy name;
- current pipeline selection, identity/lexicon scope, ontology visibility, and review profiles do
  not consult it;
- DR18 completes and normalizes this partial wiring.

Do not say that `kb.inputs` has no knowledge-store reference.

- [ ] **Step 6: Add `P0 verified baseline — 2026-07-30` under the P0 phase**

Insert the subsection after the P0 work bullets and before the P0 exit criterion. Use one compact
table with these columns:

```markdown
| Area | Verified schema/current data | Code lifecycle | P1/P2 consequence |
|---|---|---|---|
```

Include rows for:

1. artifact-object cardinality and soft object reference;
2. search partitions and non-atomic reindex;
3. connection partitions, uniqueness, and atomic scoped replacement;
4. scene-block occurrence identifier semantics;
5. cascade/input deletion and canonical-node retention;
6. knowledge-store membership and missing referential/routing semantics.

Follow the table with:

- a dated “live observations” bullet list containing the refreshed counts/distributions;
- a named “evidence inspected” list of catalog queries, migrations, and Go functions;
- an explicit statement that row counts are not normative.

- [ ] **Step 7: Correct the stale P0 benchmark paragraph**

Replace “Not yet wired to the generator, the corpus-level case kind, or the DR21 comparator” with
the verified distinction:

- the fixture, generator, resolver/coverage helpers, `CorpusDataset`, comparator, verdict scorer,
  and dedicated `gold-run`/`analyze` CLI are built;
- `gold-run` can invoke real processors through its dedicated path;
- `CorpusDataset` itself is not integrated into the existing experiment
  orchestrator/runner/store engine;
- real normalized verdict scoring remains gated by structured metric output and
  `normalize_assertions`.

Preserve the existing qualitative-versus-quantitative mock finding.

- [ ] **Step 8: Update the P0 checklist without claiming P0 exit**

Mark the deployed audit and knowledge-store inventory as verified. State that the competency
contract is frozen in Task 2 but owner approval remains pending. Keep these items open:

- domain/application owner approval;
- authoritative medical-standard editions;
- merged DR16 keyword spec;
- `semos-ontology` repository and CI;
- broader ambiguous/multilingual/unit/supersession/conflict fixtures;
- evidence for differentiated per-store pipeline policies.

Keep ADR status `Proposed`.

- [ ] **Step 9: Verify and commit Chunk 1**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
rg -n \
  "no knowledge-store reference|not wired to the generator|P0 verified baseline|CorpusDataset" \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md
git diff --check
jj diff --stat
```

Expected:

- the two stale claims return no matches;
- the new verified-baseline and remaining-integration language is present;
- whitespace check passes;
- only the consolidated ADR is changed.

Commit:

```bash
jj describe -m "docs: record SemOS P0 deployed baseline"
jj new
```

---

## Chunk 2: Competency and terminology contracts

### Task 2: Freeze the complete competency-question suite

**Files:**

- Modify: `doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`
- Source contract: `doc-repo/specs/202607/2026073004-spec-semos-p0-completion.md:40`
- Historical source: `doc-repo/research/202607/2026072302-rsch-object-centric-ontology.md:1324`

- [ ] **Step 1: Add `P0 competency-question contract` after the verified-baseline table**

Copy all 20 IDs and question texts from approved spec §2.2:

- `CQ-I01`–`CQ-I04`;
- `CQ-M01`–`CQ-M06`;
- `CQ-P01`–`CQ-P04`;
- `CQ-R01`–`CQ-R06`.

Use this ADR table shape:

```markdown
| ID | Expected answer contract | Expected result example | Positive fixture | Negative fixture | SQL test outline | P7 parity | Owner |
|---|---|---|---|---|---|---|---|
```

For each row:

- derive stable fixture IDs `<lowercase-cq-id>-positive` and `<lowercase-cq-id>-negative`;
- preserve the approved expected answer and positive/negative semantics from spec §2.2;
- include one concrete expected-result example from the table below;
- name the first executable phase;
- outline the future SQL join/selection boundary without inventing physical columns not yet
  decided;
- state `Equivalent SPARQL result required in P7`;
- preserve `Pending domain owner`, `Pending ontology owner`, or `Pending application owner`.

Example row:

```markdown
| CQ-I01 | Ordered mention refs with artifact, evidence, decision, and canonical ID | `metric:m-display-luminance` and `provision:p-display-luminance` both resolve to `object:display-module-01`, each retaining its own evidence and decision | `cq-i01-positive`: two mentions resolve to one canonical object | `cq-i01-negative`: similar mention remains separate | P2: mention links → canonical referent → decision provenance | Equivalent SPARQL result required in P7 | Pending domain owner |
```

- [ ] **Step 2: Use these concrete expected-result examples**

| ID | Required expected-result example |
|---|---|
| CQ-I01 | A metric mention and provision mention both resolve to `object:display-module-01`, each retaining separate evidence and decisions |
| CQ-I02 | `object:display-module-01` returns `ontological_level = individual`; `term:DisplayModule` returns `class` rather than the same node kind |
| CQ-I03 | `object:display-module-01` has supported classifications `DisplayModule` and `MedicalDeviceComponent`, each with its own evidence |
| CQ-I04 | `object:display-module-legacy` redirects to `object:display-module-01`; two pairwise decisions do not fabricate a third merge decision |
| CQ-M01 | Object `display-module-01` returns its luminance and touch-response assertions but no ventilator-main-unit assertion |
| CQ-M02 | “display luminance” and its approved Chinese label group under one governed property; “ambient luminance” remains separate |
| CQ-M03 | `250 cd/m²` and `250 nit` are compatible and normalize equally; a time-valued assertion is dimensionally incompatible |
| CQ-M04 | A clause using “shall be at least” is `lower_bound_requirement`; a measured test result is `observed_value` |
| CQ-M05 | A touch-response assertion returns procedure, operating condition, and effective interval; a different condition remains a separate applicability tuple |
| CQ-M06 | Two lower-bound luminance requirements with compatible units and scope return `comparable`; a missing required condition returns `indeterminate` |
| CQ-P01 | Provision `p-display-luminance` imposes assertion `a-display-luminance-min`, which constrains the luminance metric |
| CQ-P02 | The normalized assertion states that the manufacturer must verify display luminance on the display module |
| CQ-P03 | Inventory item `display-panel-001` is classified as an instance of `DisplayModule`; a label-only near match is not classified |
| CQ-P04 | `touch-controller-01` is `part_of display-module-01`; a co-mentioned component is not inferred as a part |
| CQ-R01 | Profile release `ventilator-display@0.1.0` applies because document kind, device class, jurisdiction, edition, and interval match |
| CQ-R02 | Closed profile dimension `display_metrics` yields a missing `TouchResponseTime` finding; an open dimension yields no missing finding |
| CQ-R03 | One evidence record supports and another contradicts the same assertion; missing evidence is not returned as contradiction |
| CQ-R04 | The effective superseding standard edition is selected with a precedence trace; unresolved jurisdiction conflict returns `indeterminate` |
| CQ-R05 | Provenance returns extraction run → model/prompt → candidate → human approval as an ordered audit chain |
| CQ-R06 | A proposed object merge lists the exact prior review findings whose scope would change; an unrelated merge returns an empty impact set |

- [ ] **Step 3: Add suite-wide interpretation rules**

Immediately after the table, state:

- “pending owner” means structurally frozen but not approved for P0 exit;
- missing data remains unknown unless a profile explicitly closes a dimension;
- negative fixtures guard against over-merge, accidental class promotion, unsupported inference,
  and false completeness findings;
- SQL outlines are logical contracts, not committed DDL;
- P7 parity compares result sets, not query text.

- [ ] **Step 4: Check completeness**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
for prefix in I M P R; do
  rg -o "CQ-${prefix}[0-9]{2}" \
    doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md \
    | sort -u
done
rg -o "CQ-[IMPR][0-9]{2}" \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md \
  | sort -u | wc -l

semos_expected_cq_ids=$(printf '%s\n' \
  CQ-I01 CQ-I02 CQ-I03 CQ-I04 \
  CQ-M01 CQ-M02 CQ-M03 CQ-M04 CQ-M05 CQ-M06 \
  CQ-P01 CQ-P02 CQ-P03 CQ-P04 \
  CQ-R01 CQ-R02 CQ-R03 CQ-R04 CQ-R05 CQ-R06)
semos_actual_cq_ids=$(awk -F'|' '
  /^\| CQ-[IMPR][0-9][0-9] / {
    id=$2
    gsub(/^ +| +$/, "", id)
    print id
  }
' doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md | sort -u)
test "$semos_actual_cq_ids" = "$semos_expected_cq_ids"

awk -F'|' '
  /^\| CQ-[IMPR][0-9][0-9] / {
    total++
    id=$2
    gsub(/^ +| +$/, "", id)
    seen[id]++
    if (length($4) < 10 ||
        $5 !~ /-positive/ ||
        $6 !~ /-negative/ ||
        $7 !~ /P[234]/ ||
        $8 !~ /SPARQL/ ||
        $9 !~ /Pending (domain|ontology|application) owner/) {
      bad=1
      print "invalid competency row:", id > "/dev/stderr"
    }
  }
  END {
    if (total != 20) {
      print "expected 20 competency rows, got", total > "/dev/stderr"
      exit 1
    }
    for (id in seen) {
      if (seen[id] != 1) {
        print "duplicate competency row:", id > "/dev/stderr"
        exit 1
      }
    }
    exit bad
  }
' doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md
```

Expected: the unique-ID command prints `20` and the `awk` contract check exits zero. The `awk`
check enforces exactly one row per ID plus an expected-result example, named positive/negative
fixtures, SQL phase/outline, P7 parity, and owner status.

### Task 3: Add the ontology terminology implementation crosswalk

**Files:**

- Modify: `doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`
- Source contract: `doc-repo/specs/202607/2026073004-spec-semos-p0-completion.md:134`

- [ ] **Step 1: Add `Terminology implementation contract` inside DR13**

Insert the subsection after DR13’s existing consequence paragraphs and before DR15. Copy the
support-label definitions and all 50 rows from approved spec §2.6 verbatim.

Do not shorten away:

- the distinction between `Concept`, `Class`, and `Individual`;
- the distinction between taxonomy and formal subclassing;
- the boundary separating topic/category/keyword artifacts from governed ontology terms;
- the P7-only RDF/OWL/SKOS/SHACL interchange projections;
- the reasons OWL reasoning, automatic `owl:sameAs`, SPARQL endpoint, and triple store are not
  planned.

- [ ] **Step 2: Add the default-deny extension rule**

Preserve this rule after the table:

> Any ontology-related term not in this contract is unsupported until an ADR maps it to a SemOS
> construct, lifecycle phase, and semantic boundary.

- [ ] **Step 3: Check the map against DR13**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
rg -n \
  "Terminology implementation contract|OWL reasoner|owl:sameAs|SHACL validator|SPARQL endpoint|Triple store|Topic \\||Category \\||Keyword \\|" \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md
git diff --check
```

Expected: all supported/excluded constructs appear once in the crosswalk and agree with DR13’s
four-level decision.

- [ ] **Step 4: Commit Chunk 2**

Run:

```bash
jj diff --stat
jj describe -m "docs: freeze SemOS ontology competency contracts"
jj new
```

---

## Chunk 3: Status and handoff

### Task 4: Update the ontology handoff and completion-spec status

**Files:**

- Modify: `doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md`
- Modify: `doc-repo/specs/202607/2026073004-spec-semos-p0-completion.md`
- Verify: `doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`

- [ ] **Step 1: Remove the stale session-deferral statement**

Replace the statement that the user deferred continuation with a dated continuation note:

```markdown
Work resumed on 2026-07-30 with explicit approval to complete P0 before starting P1/P2.
```

- [ ] **Step 2: Add `P0 continuation completed in this slice`**

Record:

- deployed §13.5 audit completed read-only and added to the ADR;
- ADR C5 corrected for existing `ks_store_id` partial wiring;
- knowledge stores inventoried, without inventing differentiated pipelines;
- all 20 competency questions structurally frozen with owner approval still pending;
- the 50-term implementation crosswalk added;
- stale benchmark wiring status corrected while preserving the `CorpusDataset` experiment-engine
  gap.

- [ ] **Step 3: Rewrite the remaining-P0 list**

Keep these open:

- owner approval of expected competency answers;
- authoritative standard editions and real-data worked example;
- merged DR16 keyword spec;
- `semos-ontology` repository/CI skeleton and OD7 confirmation;
- broader fixture families;
- per-document-kind baseline and evidence for store-specific pipeline policies.

State explicitly that P1 and P2 still have not started.

- [ ] **Step 4: Remove the now-fixed inconsistency section**

Replace `One inconsistency worth fixing` with a short resolved-history note pointing to the
corrected ADR P0 paragraph. Do not leave a recommendation to fix text that this slice already
fixed.

- [ ] **Step 5: Update Spec 2026073004 status**

Change:

```markdown
**Status:** Approved design, pending implementation
```

to:

```markdown
**Status:** Implemented — P0 documentation baseline recorded
```

Add one implementation-result sentence naming ADR `2026072901` and handoff `2026073002`.

- [ ] **Step 6: Answer the workspace documentation protocol in the ADR**

Update ADR `Documentation Impact` so it answers:

- **What knowledge changed?** Deployed current-state contracts, competency suite, terminology
  support boundaries, and remaining P0 blockers.
- **Which docs/specs/ADRs/tests are affected?** ADR `2026072901`, Spec `2026073004`, handoff
  `2026073002`; no code tests.
- **Which docs were updated?** Those three documents.
- **Which docs are now stale?** Two superseded keyword specs remain unmerged; code capsules remain
  future-phase work.
- **What was intentionally left undocumented?** Future DDL, executable future-schema SQL,
  authoritative standard content, governance person assignments, and hosting credentials.

- [ ] **Step 7: Run final verification**

Run:

```bash
cd /Users/cding/Workspace/KnowledgeStore
semos_expected_cq_ids=$(printf '%s\n' \
  CQ-I01 CQ-I02 CQ-I03 CQ-I04 \
  CQ-M01 CQ-M02 CQ-M03 CQ-M04 CQ-M05 CQ-M06 \
  CQ-P01 CQ-P02 CQ-P03 CQ-P04 \
  CQ-R01 CQ-R02 CQ-R03 CQ-R04 CQ-R05 CQ-R06)
semos_actual_cq_ids=$(awk -F'|' '
  /^\| CQ-[IMPR][0-9][0-9] / {
    id=$2
    gsub(/^ +| +$/, "", id)
    print id
  }
' doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md | sort -u)
test "$semos_actual_cq_ids" = "$semos_expected_cq_ids"

awk -F'|' '
  /^\| CQ-[IMPR][0-9][0-9] / {
    total++
    id=$2
    gsub(/^ +| +$/, "", id)
    seen[id]++
    if (length($4) < 10 ||
        $5 !~ /-positive/ ||
        $6 !~ /-negative/ ||
        $7 !~ /P[234]/ ||
        $8 !~ /SPARQL/ ||
        $9 !~ /Pending (domain|ontology|application) owner/) {
      bad=1
    }
  }
  END {
    if (total != 20) exit 1
    for (id in seen) if (seen[id] != 1) exit 1
    exit bad
  }
' doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md

test "$(awk '
  /^#### Terminology implementation contract/ { in_map=1; next }
  in_map && /^\\| General term / { in_table=1; next }
  in_table && /^\\|---/ { next }
  in_table && /^\\|/ { count++; next }
  in_table && !/^\\|/ { print count; exit }
' doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md)" = "50"

! rg -n \
  "kb\\.inputs carries \\*\\*no\\*\\* knowledge-store reference|Not yet wired to the generator|One inconsistency worth fixing|I will decide when to continue" \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md \
  doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md

rg -n \
  "^\\*\\*Status:\\*\\* Proposed|P1 and P2.*not started|Pending (domain|ontology|application) owner|CorpusDataset.*not integrated" \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md \
  doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md

for file_path in \
  doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md \
  doc-repo/specs/202607/2026073004-spec-semos-p0-completion.md \
  doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md; do
  test -f "$file_path"
done

git diff --check
jj diff --stat
```

Expected:

- exactly 20 unique competency IDs;
- exactly 50 terminology rows;
- no stale claims;
- ADR remains Proposed;
- owner approval and P1/P2 status remain explicit;
- all files resolve;
- whitespace check passes;
- only the ADR, completion spec, and ontology handoff changed since the preceding commit.

- [ ] **Step 8: Commit the completed P0 documentation slice**

Run:

```bash
jj describe -m "docs: complete SemOS P0 ontology documentation"
jj new
jj status
jj log -r '@---::@-' --no-graph
```

Expected:

- final working copy is clean;
- the execution produced three focused documentation commits;
- no ChenWeb code or database state changed.

## Knowledge deliberately left for later plans

- DR16 keyword-spec merge;
- creation and CI of the separate `semos-ontology` repository;
- authoritative medical-standard source selection;
- fixture-corpus expansion;
- P1 pipeline-plane implementation;
- P2 ontology compiler, core modules, and canonicalization kernel.

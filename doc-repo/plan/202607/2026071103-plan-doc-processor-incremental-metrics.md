# Doc Processor Incremental Metrics (ADR 2026071002) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement ADR `KnowledgeStore/doc-repo/adrs/202607/2026071002-adr-doc-processor-incremental.md` (DR1-DR4): a `force_clear` flag independent of the existing `force` flag, incremental merge of newly-extracted metrics with previously-persisted ones (Metric Groups, Rule-1..4, Merge Resolution LLM call), stable artifact IDs across runs, and a dirty-check that only writes/logs metrics that actually changed.

**Architecture:** All logic lands in `MetricsProcessor`'s `InitChunkBatch`/`ProcessChunk`/`FinalizeChunkBatch` (the `ChunkBatchProcessor` interface), **not** `HandleEvent` — see "Critical Finding" below for why. `force`/`force_clear` are threaded from the event payload into these methods via `context.Context` (mirroring the existing `withLLMRecordID` pattern), since `InitChunkBatch`'s signature doesn't carry the raw event. Merge logic lives in two new files (`metrics_merge.go`, `metrics_merge_resolve.go`) rather than growing the already-2675-line `extract-metrics.go` further. Persistence uses a Postgres `INSERT ... ON CONFLICT (input_record_id, metric_id) DO UPDATE` (new unique constraint), called only for metrics the Go-side merge logic has already determined are new-or-changed — Postgres never sees, and never touches, unchanged existing rows.

**Tech Stack:** Go 1.25, `database/sql` + `lib/pq`-style Postgres driver, goose migrations, Svelte 5 frontend, plain `testing` package (no testify) for Go tests.

## Critical Finding — read before starting

The ADR's DR1 was written assuming `MetricsProcessor.HandleEvent`'s `if evt.Force {...} else {...}` block (lines 337-353) is the live force/skip mechanism. **It is not**, on the path that actually runs today:

- `chunk_batch_coordinator.go:runPhaseBProcessors` (line 360) only falls back to the legacy `HandleEvent`-per-processor path (`runProcessorsTwoPhase`) when `len(part.batch) <= 1`. Nine processors (including metrics) implement `ChunkBatchProcessor`, so this is never true in practice.
- `runProcessorsChunkBatched` (`chunk_batch_coordinator.go:51-227`) parses the event (line 74) but never reads `evt.Force` again, and never calls `HandleEvent` for batch-capable processors — only `InitChunkBatch` → `scheduleChunkBatch` (which calls `ProcessChunk`) → `FinalizeChunkBatch`.
- `MetricsProcessor.FinalizeChunkBatch` (lines 2636-2675) calls `Store.SaveMetrics` unconditionally: no `MetricsExist` check, no `DeleteMetricsByInputRecordID` call. Same is true of `ProvisionsProcessor`, `InventoryItemsProcessor`, `EntityProcessor`, `RelationProcessor`'s `FinalizeChunkBatch`.
- `kb.metrics` has no unique constraint on `metric_id`, which is assembled as `fmt.Sprintf("%d_mtc_%d", recordID, i+1)` — restarting at 1 every run.

**Net effect today:** every re-run of `extract_metrics` (and the other three processors) via the live coordinator path blindly appends a fresh full set of rows, with colliding `metric_id`s, regardless of `force`. This plan fixes that as part of implementing the ADR (DR1 requires `force_clear` semantics to actually hold; they can't unless the underlying skip/wipe guard exists on the live path).

Confirmed with the user: build directly on `InitChunkBatch`/`ProcessChunk`/`FinalizeChunkBatch`; leave `HandleEvent` untouched (dead code, but touching it fixes nothing on the live path and isn't asked for — do not delete it, per "Surgical Changes": don't remove pre-existing code unless asked).

## Global Constraints

- Prompts must be saved under `prompts/`, filenames `prompt-<name>-v<n>.md`, never hard-coded in Go source (ChenWeb `CLAUDE.md` §2).
- Minimum code that solves the problem; no speculative abstractions; match existing style (ChenWeb `CLAUDE.md` §1.2-1.3).
- Touch only what you must; don't refactor unrelated code (ChenWeb `CLAUDE.md` §1.3).
- Schema changes go through goose migrations in `project_migrations/` (`Workspace/CLAUDE.md`).
- Protect Postgres reserved keywords in any new column/constraint names (`Workspace/CLAUDE.md`).
- Commit with `jj`, one commit per task (`Workspace/CLAUDE.md` Git Workflow — this repo uses jj, confirmed by `.jj/` at `/Users/cding/Workspace/ChenWeb`).
- Go 1.25.0+, workspace-aware (`go.work` at `/Users/cding/Workspace`).

---

### Task 1: `force_clear` field on the shared event type

**Files:**
- Modify: `server/api/doc-processing/event.go:17-54`
- Test: `server/api/doc-processing/event_test.go`

**Interfaces:**
- Produces: `LineFileGeneratedEvent.ForceClear bool` — read by later tasks via context, not directly on the struct (see Task 2).

- [ ] **Step 1: Write the failing test**

Add to `server/api/doc-processing/event_test.go`:

```go
func TestParseLineFileGeneratedEvent_ForceClearDefaultsFalse(t *testing.T) {
	evt, err := ParseLineFileGeneratedEvent([]byte(`{"record_id":"42","force":true}`))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if evt.ForceClear != false {
		t.Fatalf("ForceClear = %v, want false when omitted", evt.ForceClear)
	}
}

func TestParseLineFileGeneratedEvent_ForceClearTrue(t *testing.T) {
	evt, err := ParseLineFileGeneratedEvent([]byte(`{"record_id":"42","force":true,"force_clear":true}`))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if evt.ForceClear != true {
		t.Fatalf("ForceClear = %v, want true", evt.ForceClear)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run TestParseLineFileGeneratedEvent_ForceClear -v`
Expected: FAIL — `evt.ForceClear undefined (type LineFileGeneratedEvent has no field or method ForceClear)`

- [ ] **Step 3: Add the field and parsing**

In `server/api/doc-processing/event.go`, modify the struct (line 17-24):

```go
type LineFileGeneratedEvent struct {
	RecordID   int64
	Filename   string
	Force      bool
	ForceClear bool
	Type       string
	Status     string
	Operations []string
}
```

And in `ParseLineFileGeneratedEvent` (line 26-54), after the existing `force` block:

```go
	force := true
	if v, ok := raw["force"]; ok {
		b, bErr := asBool(v, true)
		if bErr != nil {
			return LineFileGeneratedEvent{}, fmt.Errorf("invalid force: %w", bErr)
		}
		force = b
	}

	forceClear := false
	if v, ok := raw["force_clear"]; ok {
		b, bErr := asBool(v, false)
		if bErr != nil {
			return LineFileGeneratedEvent{}, fmt.Errorf("invalid force_clear: %w", bErr)
		}
		forceClear = b
	}

	return LineFileGeneratedEvent{
		RecordID:   rid,
		Filename:   firstNonEmptyTrimmed(asString(raw["filename"]), asString(raw["line_file_filename"])),
		Force:      force,
		ForceClear: forceClear,
		Type:       strings.ToLower(strings.TrimSpace(asString(raw["type"]))),
		Status:     strings.ToLower(strings.TrimSpace(asString(raw["status"]))),
		Operations: parseOperations(raw["operation"]),
	}, nil
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run TestParseLineFileGeneratedEvent_ForceClear -v`
Expected: PASS (both tests)

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(doc-processing): add force_clear field to LineFileGeneratedEvent"
```

---

### Task 2: Thread `force`/`force_clear` through context for the chunk-batch coordinator

**Files:**
- Create: `server/api/doc-processing/doc_processor_flags_context.go`
- Modify: `server/api/doc-processing/chunk_batch_coordinator.go:74-84`
- Test: `server/api/doc-processing/doc_processor_flags_context_test.go`

**Interfaces:**
- Produces: `withDocProcessorFlags(ctx context.Context, force, forceClear bool) context.Context`, `docProcessorFlagsFromContext(ctx context.Context) (force, forceClear bool)`. Default when absent from context: `force=true, forceClear=false` (matches the event-level defaults, so any caller that doesn't wrap the context gets today's "always run, never wipe-only" behavior — actually matches "run, merge" — see Task 6 for why `forceClear` defaulting to `false` is correct: merge is the safe default, not wipe).
- Consumed by: Task 6 (`MetricsProcessor.InitChunkBatch`), Task 12 (other three processors).

- [ ] **Step 1: Write the failing test**

Create `server/api/doc-processing/doc_processor_flags_context_test.go`:

```go
package docprocessing

import (
	"context"
	"testing"
)

func TestDocProcessorFlagsContext_RoundTrip(t *testing.T) {
	ctx := withDocProcessorFlags(context.Background(), false, true)
	force, forceClear := docProcessorFlagsFromContext(ctx)
	if force != false || forceClear != true {
		t.Fatalf("got force=%v forceClear=%v, want false,true", force, forceClear)
	}
}

func TestDocProcessorFlagsContext_DefaultsWhenAbsent(t *testing.T) {
	force, forceClear := docProcessorFlagsFromContext(context.Background())
	if force != true || forceClear != false {
		t.Fatalf("got force=%v forceClear=%v, want true,false (defaults)", force, forceClear)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run TestDocProcessorFlagsContext -v`
Expected: FAIL — `undefined: withDocProcessorFlags`

- [ ] **Step 3: Implement, mirroring `llm_capture_input.go`'s `withLLMRecordID` pattern**

Create `server/api/doc-processing/doc_processor_flags_context.go`:

```go
package docprocessing

import "context"

type docProcessorFlagsKey struct{}

type docProcessorFlags struct {
	force      bool
	forceClear bool
}

// withDocProcessorFlags attaches the event-level force/force_clear flags to
// ctx so per-chunk-batch lifecycle methods (InitChunkBatch/ProcessChunk/
// FinalizeChunkBatch) can read them without a signature change to the
// shared ChunkBatchProcessor interface (ADR 2026071002 DR1).
func withDocProcessorFlags(ctx context.Context, force, forceClear bool) context.Context {
	return context.WithValue(ctx, docProcessorFlagsKey{}, docProcessorFlags{force: force, forceClear: forceClear})
}

// docProcessorFlagsFromContext returns the attached flags, or (true, false)
// if none were attached — matching the event-level defaults (force defaults
// to true, force_clear defaults to false).
func docProcessorFlagsFromContext(ctx context.Context) (force, forceClear bool) {
	if ctx == nil {
		return true, false
	}
	f, ok := ctx.Value(docProcessorFlagsKey{}).(docProcessorFlags)
	if !ok {
		return true, false
	}
	return f.force, f.forceClear
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run TestDocProcessorFlagsContext -v`
Expected: PASS (both tests)

- [ ] **Step 5: Wire it into the coordinator**

In `chunk_batch_coordinator.go`, `runProcessorsChunkBatched`, right after the existing event parse (line 74-84):

```go
	evt, err := ParseLineFileGeneratedEvent(payload)
	if err != nil {
		if s.Logger != nil {
			s.Logger.Error("chunk batch: parse event failed", "record_id", recordID, "error", err)
		}
		*requestFailed = true
		*firstErr = fmt.Errorf("(MID_26062701) chunk batch parse event: %w", err)
		phaseBSpan.SetStatus(codes.Error, (*firstErr).Error())
		recordError(phaseBSpan, err)
		return
	}
	ctx = withDocProcessorFlags(ctx, evt.Force, evt.ForceClear)
```

(One line added after the existing `if err != nil { ... return }` block — `ctx` is subsequently used unchanged by every `bp.InitChunkBatch(recCtx, ...)` call at line 162, since those build `recCtx := withLLMRecordID(ctx, recordID)` from this same `ctx`.)

- [ ] **Step 6: Run the full doc-processing package test suite**

Run: `cd server && go test ./api/doc-processing/... -v 2>&1 | tail -40`
Expected: PASS, no regressions (this change is additive — existing tests don't read the new context value)

- [ ] **Step 7: Commit**

```bash
jj commit -m "feat(doc-processing): thread force/force_clear flags through context for chunk-batch coordinator"
```

---

### Task 3: Migration — unique constraint on `kb.metrics(input_record_id, metric_id)`

**Files:**
- Create: `project_migrations/20260711000001_add_kb_metrics_unique_constraint.sql`

**Interfaces:**
- Produces: unique index `kb_metrics_record_metric_id_uniq` on `kb.metrics(input_record_id, metric_id)` — required by Task 5's `ON CONFLICT (input_record_id, metric_id)` upsert.

**Why this is needed, and why it's a new migration item the ADR didn't originally call for:** the live-bug in the Critical Finding above means some records may already have duplicate `(input_record_id, metric_id)` pairs (e.g. two separate runs both producing `"173_mtc_1"`). A unique constraint can't be added over duplicate data, so this migration first deduplicates, keeping the lowest `id` (earliest-inserted row) per `(input_record_id, metric_id)` pair, then adds the constraint. `metric_id` can be NULL for old rows predating the `_mtc_` scheme; Postgres unique constraints treat NULLs as distinct from each other, so NULL `metric_id` rows are never considered duplicates of one another and are unaffected.

- [ ] **Step 1: Write the migration file**

Create `project_migrations/20260711000001_add_kb_metrics_unique_constraint.sql`:

```sql
-- +goose Up
DELETE FROM kb.metrics a USING kb.metrics b
WHERE a.metric_id IS NOT NULL
  AND a.metric_id = b.metric_id
  AND a.input_record_id = b.input_record_id
  AND a.id > b.id;

CREATE UNIQUE INDEX IF NOT EXISTS kb_metrics_record_metric_id_uniq
    ON kb.metrics (input_record_id, metric_id)
    WHERE metric_id IS NOT NULL;

-- +goose Down
DROP INDEX IF EXISTS kb_metrics_record_metric_id_uniq;
```

- [ ] **Step 2: Run the migration locally**

Run: `cd /Users/cding/Workspace/ChenWeb && mise run migrate-up` (or the project's documented goose invocation — check `tax/CLAUDE.md`-equivalent doc for ChenWeb's exact task name if `mise run migrate-up` doesn't exist; confirm via `mise tasks` first)
Expected: migration applies with no error; if duplicates existed, the log shows rows deleted.

- [ ] **Step 3: Verify the constraint**

Run: `psql "$DATABASE_URL" -c "\d kb.metrics" | grep kb_metrics_record_metric_id_uniq`
Expected: the unique index is listed.

- [ ] **Step 4: Commit**

```bash
jj commit -m "fix(db): dedupe kb.metrics and add unique (input_record_id, metric_id) constraint"
```

---

### Task 4: `MetricsStore` gains `GetMetricsByInputRecordID` and `UpsertMetrics`

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go:100-104` (interface), `:2172` area (add new method near `SaveMetrics`)
- Test: `server/api/doc-processing/extract-metrics_test.go`

**Interfaces:**
- Produces:
  - `MetricsStore.GetMetricsByInputRecordID(ctx context.Context, inputRecordID int64) ([]map[string]any, error)` — returns every persisted column as a `map[string]any` (same shape as what's passed into `SaveMetrics`), including `metric_id`, `id` (as `"id"`, int64), and all substantive fields.
  - `MetricsStore.UpsertMetrics(ctx context.Context, req SaveMetricsRequest) (int64, error)` — same request shape as `SaveMetrics`; internally an `INSERT ... ON CONFLICT (input_record_id, metric_id) DO UPDATE`. Caller (Task 8) is responsible for only passing metrics it has already determined are new-or-changed — this method does not itself skip anything.
- Consumed by: Task 8 (`FinalizeChunkBatch`'s persistence step).

- [ ] **Step 1: Write the failing tests**

Add to `server/api/doc-processing/extract-metrics_test.go`. First extend `fakeMetricsStore` (existing at lines 55-89) with the two new methods so it still satisfies `MetricsStore` for other tests in the file:

```go
type fakeMetricsStore struct {
	exists            bool
	existsErr         error
	saveErr           error
	deleteErr         error
	deleteCalled      int
	saveCalled        int
	lastSave          SaveMetricsRequest
	metricsExistCalls int
	existingMetrics   []map[string]any
	getExistingErr    error
	upsertErr         error
	upsertCalled      int
	lastUpsert        SaveMetricsRequest
}

func (f *fakeMetricsStore) GetMetricsByInputRecordID(_ context.Context, _ int64) ([]map[string]any, error) {
	if f.getExistingErr != nil {
		return nil, f.getExistingErr
	}
	return f.existingMetrics, nil
}

func (f *fakeMetricsStore) UpsertMetrics(_ context.Context, req SaveMetricsRequest) (int64, error) {
	f.upsertCalled++
	f.lastUpsert = req
	if f.upsertErr != nil {
		return 0, f.upsertErr
	}
	return int64(len(req.Metrics)), nil
}
```

Then a real-SQL test using the existing `sqlmock` pattern already imported in this test file (confirmed present per the file's import block):

```go
func TestMetricsSQLStore_UpsertMetrics_OnConflictUpdatesOnlyGivenRows(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	store := MetricsSQLStore{DB: db}
	mock.ExpectExec(`CREATE SCHEMA IF NOT EXISTS kb`).WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectExec(`INSERT INTO kb\.metrics`).
		WithArgs(sqlmock.AnyArg(), int64(173), "173_mtc_1", sqlmock.AnyArg(), sqlmock.AnyArg(),
			sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(),
			sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(),
			sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(),
			sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(),
			sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(),
			sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(),
			sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	n, err := store.UpsertMetrics(context.Background(), SaveMetricsRequest{
		InputRecordID: 173,
		Metrics: []map[string]any{
			{"metric_id": "173_mtc_1", "metric_name": "Latency", "source_line_spans": []any{float64(2)}},
		},
	})
	if err != nil {
		t.Fatalf("UpsertMetrics: %v", err)
	}
	if n != 1 {
		t.Fatalf("n=%d, want 1", n)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run TestMetricsSQLStore_UpsertMetrics -v`
Expected: FAIL — `store.UpsertMetrics undefined`

- [ ] **Step 3: Implement `GetMetricsByInputRecordID`**

In `extract-metrics.go`, add the method to the interface (line 100-104):

```go
type MetricsStore interface {
	MetricsExist(ctx context.Context, inputRecordID int64) (bool, error)
	DeleteMetricsByInputRecordID(ctx context.Context, inputRecordID int64) (int64, error)
	SaveMetrics(ctx context.Context, req SaveMetricsRequest) (int64, error)
	GetMetricsByInputRecordID(ctx context.Context, inputRecordID int64) ([]map[string]any, error)
	UpsertMetrics(ctx context.Context, req SaveMetricsRequest) (int64, error)
}
```

Add the implementation near `MetricsExist` (after line ~2159):

```go
func (s MetricsSQLStore) GetMetricsByInputRecordID(ctx context.Context, inputRecordID int64) ([]map[string]any, error) {
	if err := s.ensureMetricsTable(ctx); err != nil {
		return nil, err
	}
	const q = `
SELECT id, metric_id, metric_name, metric_name_en, source_line_spans, metric_subject,
       metric_subject_en, metric_desc, metric_desc_en, metric_context, metric_context_en,
       metric_keywords, metric_keywords_en, metric_unit, metric_unit_en, metric_value,
       value_data_type, value_range_type, value_class, value_class_en,
       formula_or_definition, threshold_or_target, measurement_frequency,
       metric_categories, metric_categories_en, ext_info
FROM kb.metrics
WHERE input_record_id = $1`
	rows, err := s.DB.QueryContext(ctx, q, inputRecordID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []map[string]any
	for rows.Next() {
		var (
			id                                                                          int64
			metricID, name, nameEn, subject, subjectEn, desc, descEn, ctx1, ctxEn         sql.NullString
			unit, unitEn, value, valueDataType, valueRangeType, valueClass, valueClassEn  sql.NullString
			formula, threshold, freq, categories, categoriesEn                           sql.NullString
			spansJSON, keywordsJSON, keywordsEnJSON, extInfoJSON                         sql.NullString
		)
		if err := rows.Scan(&id, &metricID, &name, &nameEn, &spansJSON, &subject, &subjectEn,
			&desc, &descEn, &ctx1, &ctxEn, &keywordsJSON, &keywordsEnJSON, &unit, &unitEn, &value,
			&valueDataType, &valueRangeType, &valueClass, &valueClassEn, &formula, &threshold, &freq,
			&categories, &categoriesEn, &extInfoJSON); err != nil {
			return nil, err
		}
		m := map[string]any{
			"id": id, "metric_id": metricID.String, "metric_name": name.String,
			"metric_name_en": nameEn.String, "metric_subject": subject.String,
			"metric_subject_en": subjectEn.String, "metric_desc": desc.String,
			"metric_desc_en": descEn.String, "metric_context": ctx1.String,
			"metric_context_en": ctxEn.String, "metric_unit": unit.String,
			"metric_unit_en": unitEn.String, "metric_value": value.String,
			"value_data_type": valueDataType.String, "value_range_type": valueRangeType.String,
			"value_class": valueClass.String, "value_class_en": valueClassEn.String,
			"formula_or_definition": formula.String, "threshold_or_target": threshold.String,
			"measurement_frequency": freq.String,
		}
		if spansJSON.Valid {
			var spans any
			_ = json.Unmarshal([]byte(spansJSON.String), &spans)
			m["source_line_spans"] = spans
		}
		if keywordsJSON.Valid {
			var kw any
			_ = json.Unmarshal([]byte(keywordsJSON.String), &kw)
			m["metric_keywords"] = kw
		}
		if categories.Valid {
			var cats any
			_ = json.Unmarshal([]byte(categories.String), &cats)
			m["metric_categories"] = cats
		}
		if extInfoJSON.Valid {
			var ext map[string]any
			_ = json.Unmarshal([]byte(extInfoJSON.String), &ext)
			m["ext_info"] = ext
		}
		out = append(out, m)
	}
	return out, rows.Err()
}
```

- [ ] **Step 4: Implement `UpsertMetrics`**

Add near `SaveMetrics` (after line ~2320, wherever `SaveMetrics` currently ends), reusing the same per-row field-building logic as `SaveMetrics` but with `ON CONFLICT`:

```go
func (s MetricsSQLStore) UpsertMetrics(ctx context.Context, req SaveMetricsRequest) (int64, error) {
	if err := s.ensureMetricsTable(ctx); err != nil {
		return 0, err
	}
	if len(req.Metrics) == 0 {
		return 0, nil
	}

	const stmt = `
INSERT INTO kb.metrics (
	event_id, input_record_id, metric_id, metric_name, metric_name_en, source_line_spans,
	metric_subject, metric_subject_en, metric_desc, metric_desc_en, metric_context, metric_context_en,
	metric_keywords, metric_keywords_en, model_name, prompt_name, location_type, metric_unit, metric_unit_en,
	metric_value, value_data_type, value_range_type, value_class, value_class_en, formula_or_definition,
	threshold_or_target, measurement_frequency, confidence, is_explicit_metric, table_name_or_section,
	reasoning_tags, metric_categories, metric_categories_en, category_paths, category_paths_en,
	search_document, ext_info
) VALUES (
	$1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10,$11,$12,$13::jsonb,$14::jsonb,$15,$16,$17,$18,$19,$20,$21,$22,$23,
	$24,$25,$26,$27,$28,$29,$30,$31::jsonb,$32,$33,$34::jsonb,$35::jsonb,$36,$37::jsonb
)
ON CONFLICT (input_record_id, metric_id) WHERE metric_id IS NOT NULL DO UPDATE SET
	metric_name = EXCLUDED.metric_name, metric_name_en = EXCLUDED.metric_name_en,
	source_line_spans = EXCLUDED.source_line_spans, metric_subject = EXCLUDED.metric_subject,
	metric_subject_en = EXCLUDED.metric_subject_en, metric_desc = EXCLUDED.metric_desc,
	metric_desc_en = EXCLUDED.metric_desc_en, metric_context = EXCLUDED.metric_context,
	metric_context_en = EXCLUDED.metric_context_en, metric_keywords = EXCLUDED.metric_keywords,
	metric_keywords_en = EXCLUDED.metric_keywords_en, metric_unit = EXCLUDED.metric_unit,
	metric_unit_en = EXCLUDED.metric_unit_en, metric_value = EXCLUDED.metric_value,
	value_data_type = EXCLUDED.value_data_type, value_range_type = EXCLUDED.value_range_type,
	value_class = EXCLUDED.value_class, value_class_en = EXCLUDED.value_class_en,
	formula_or_definition = EXCLUDED.formula_or_definition, threshold_or_target = EXCLUDED.threshold_or_target,
	measurement_frequency = EXCLUDED.measurement_frequency, metric_categories = EXCLUDED.metric_categories,
	metric_categories_en = EXCLUDED.metric_categories_en, category_paths = EXCLUDED.category_paths,
	category_paths_en = EXCLUDED.category_paths_en, search_document = EXCLUDED.search_document,
	ext_info = EXCLUDED.ext_info`

	isEnglish := strings.EqualFold(strings.TrimSpace(req.Language), "en") ||
		strings.EqualFold(strings.TrimSpace(req.Language), "english")
	var eventIDVal any
	if id := strings.TrimSpace(req.EventID); id != "" {
		eventIDVal = id
	}

	var affected int64
	for _, metric := range req.Metrics {
		sourceSpansJSON, _ := json.Marshal(metric["source_line_spans"])
		keywordsJSON, _ := json.Marshal(metric["keywords"])
		reasoningTagsJSON, _ := json.Marshal(metric["reasoning_tags"])
		extInfo, _ := json.Marshal(metric["ext_info"])

		var metricNameEn, subjectEn, descEn, contextEn, keywordsEnVal, unitEn, valueClassEn any
		if !isEnglish {
			metricNameEn = strings.TrimSpace(asString(metric["metric_name_en"]))
			subjectEn = strings.TrimSpace(asString(metric["subject_en"]))
			descEn = strings.TrimSpace(asString(metric["desc_en"]))
			contextEn = strings.TrimSpace(asString(metric["context_en"]))
			kw, _ := json.Marshal(metric["keywords_en"])
			keywordsEnVal = string(kw)
			unitEn = strings.TrimSpace(asString(metric["unit_en"]))
			valueClassEn = strings.TrimSpace(asString(metric["value_class_en"]))
		}

		searchDocument := buildMetricSearchDocument(metric, !isEnglish)
		metricCategoriesJSON, _ := json.Marshal(metricCategoryKeysFromMetric(metric))
		metricCategoriesEnJSON, _ := json.Marshal(metricCategoryKeysFromValue(metric["metric_categories_en"]))
		categoryPathsJSON, _ := json.Marshal(metric["category_paths"])
		categoryPathsEnJSON, _ := json.Marshal(metric["category_paths_en"])

		res, err := s.DB.ExecContext(ctx, stmt,
			eventIDVal, req.InputRecordID, strings.TrimSpace(asString(metric["metric_id"])),
			strings.TrimSpace(asString(metric["metric_name"])), metricNameEn, string(sourceSpansJSON),
			strings.TrimSpace(asString(metric["subject"])), subjectEn,
			strings.TrimSpace(asString(metric["desc"])), descEn,
			strings.TrimSpace(asString(metric["context"])), contextEn,
			string(keywordsJSON), keywordsEnVal, req.ModelName, req.PromptName,
			strings.TrimSpace(asString(metric["location_type"])),
			strings.TrimSpace(asString(metric["unit"])), unitEn,
			strings.TrimSpace(asString(metric["metric_value"])),
			strings.TrimSpace(asString(metric["value_data_type"])),
			strings.TrimSpace(asString(metric["value_range_type"])),
			strings.TrimSpace(asString(metric["value_class"])), valueClassEn,
			strings.TrimSpace(asString(metric["formula_or_definition"])),
			strings.TrimSpace(asString(metric["threshold_or_target"])),
			strings.TrimSpace(asString(metric["measurement_frequency"])),
			metric["confidence"], metric["is_explicit_metric"],
			strings.TrimSpace(asString(metric["table_name_or_section"])), string(reasoningTagsJSON),
			string(metricCategoriesJSON), string(metricCategoriesEnJSON), string(categoryPathsJSON),
			string(categoryPathsEnJSON), searchDocument, string(extInfo),
		)
		if err != nil {
			return affected, err
		}
		n, _ := res.RowsAffected()
		affected += n
	}
	return affected, nil
}
```

*(Note: `req.Metrics[i]["ext_info"]` is expected to already be a `map[string]any` built by the caller — Task 8 — unlike `SaveMetrics` which hard-codes `ext_info` internally. This is intentional: DR2's inline merge log needs per-metric content the store layer shouldn't have to know about.)*

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run 'TestMetricsSQLStore_UpsertMetrics|TestMetricsSQLStore_GetMetricsByInputRecordID' -v`
Expected: PASS

- [ ] **Step 6: Run full package tests (fakeMetricsStore now satisfies the wider interface)**

Run: `cd server && go build ./... && go test ./api/doc-processing/... 2>&1 | tail -40`
Expected: builds clean, no regressions (every other `MetricsStore` implementer/fake in the package must also gain the two new methods — grep first: `grep -rn "MetricsStore{}\|) MetricsStore\b" server/api/doc-processing/*_test.go`, add stub methods to any other fakes found).

- [ ] **Step 7: Commit**

```bash
jj commit -m "feat(metrics): add GetMetricsByInputRecordID and UpsertMetrics to MetricsStore"
```

---

### Task 5: `metrics_merge.go` — Metric Groups (transitive closure) and Rule-1 identity

**Files:**
- Create: `server/api/doc-processing/metrics_merge.go`
- Test: `server/api/doc-processing/metrics_merge_test.go`

**Interfaces:**
- Produces:
  - `metricsIdentical(a, b map[string]any) bool` — Rule-1 (5-field exact match).
  - `metricLineSpansOverlap(a, b map[string]any) bool` — line-span overlap check via existing `normalizeSourceLineSpans`.
  - `computeMetricGroups(metrics []map[string]any) [][]int` — connected components (union-find) over index positions in `metrics`, edge iff `metricLineSpansOverlap`.
- Consumed by: Task 6 (`mergeMetrics`).

- [ ] **Step 1: Write the failing tests**

Create `server/api/doc-processing/metrics_merge_test.go`:

```go
package docprocessing

import "testing"

func TestMetricsIdentical_SameFieldsMatch(t *testing.T) {
	a := map[string]any{
		"metric_name": "Latency", "metric_subject": "gateway", "metric_unit": "ms",
		"metric_value": "200", "source_line_spans": []any{float64(2)},
	}
	b := map[string]any{
		"metric_name": "Latency", "metric_subject": "gateway", "metric_unit": "ms",
		"metric_value": "200", "source_line_spans": []any{float64(2)},
	}
	if !metricsIdentical(a, b) {
		t.Fatalf("expected identical")
	}
}

func TestMetricsIdentical_DifferentValueNotMatch(t *testing.T) {
	a := map[string]any{
		"metric_name": "Latency", "metric_subject": "gateway", "metric_unit": "ms",
		"metric_value": "200", "source_line_spans": []any{float64(2)},
	}
	b := map[string]any{
		"metric_name": "Latency", "metric_subject": "gateway", "metric_unit": "ms",
		"metric_value": "300", "source_line_spans": []any{float64(2)},
	}
	if metricsIdentical(a, b) {
		t.Fatalf("expected not identical")
	}
}

func TestMetricLineSpansOverlap_True(t *testing.T) {
	a := map[string]any{"source_line_spans": []any{float64(2), float64(3)}}
	b := map[string]any{"source_line_spans": []any{"3:4"}}
	if !metricLineSpansOverlap(a, b) {
		t.Fatalf("expected overlap (both cover line 3)")
	}
}

func TestMetricLineSpansOverlap_False(t *testing.T) {
	a := map[string]any{"source_line_spans": []any{float64(2)}}
	b := map[string]any{"source_line_spans": []any{float64(9)}}
	if metricLineSpansOverlap(a, b) {
		t.Fatalf("expected no overlap")
	}
}

// TestComputeMetricGroups_TransitiveChain regression-tests the single-hop bug
// the ADR calls out: A overlaps B, B overlaps C, but A and C do not directly
// overlap. All three must land in one group.
func TestComputeMetricGroups_TransitiveChain(t *testing.T) {
	metrics := []map[string]any{
		{"source_line_spans": []any{float64(1), float64(2)}},  // A: lines 1-2
		{"source_line_spans": []any{float64(2), float64(3)}},  // B: lines 2-3 (overlaps A)
		{"source_line_spans": []any{float64(3), float64(4)}},  // C: lines 3-4 (overlaps B, not A)
		{"source_line_spans": []any{float64(100)}},            // D: unrelated
	}
	groups := computeMetricGroups(metrics)
	if len(groups) != 2 {
		t.Fatalf("groups=%d, want 2 (one of size 3, one of size 1); got %+v", len(groups), groups)
	}
	var sizes []int
	for _, g := range groups {
		sizes = append(sizes, len(g))
	}
	found3, found1 := false, false
	for _, s := range sizes {
		if s == 3 {
			found3 = true
		}
		if s == 1 {
			found1 = true
		}
	}
	if !found3 || !found1 {
		t.Fatalf("expected group sizes [3,1], got %v", sizes)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run 'TestMetricsIdentical|TestMetricLineSpansOverlap|TestComputeMetricGroups' -v`
Expected: FAIL — undefined functions

- [ ] **Step 3: Implement**

Create `server/api/doc-processing/metrics_merge.go`:

```go
package docprocessing

import "strings"

// metricsIdentical implements ADR 2026071002 DR2 Rule-1: two metrics are the
// same if these five fields match exactly (mirrors normalizedMetricCandidateKey's
// field set in dedupeFinalMetricRows, extract-metrics.go).
func metricsIdentical(a, b map[string]any) bool {
	fields := []string{"metric_name", "metric_subject", "metric_unit", "metric_value"}
	for _, f := range fields {
		if strings.TrimSpace(asString(a[f])) != strings.TrimSpace(asString(b[f])) {
			return false
		}
	}
	spansA := strings.Join(normalizeSourceLineSpans(a["source_line_spans"]), ",")
	spansB := strings.Join(normalizeSourceLineSpans(b["source_line_spans"]), ",")
	return spansA == spansB
}

// metricLineSpansOverlap reports whether two metrics share at least one source line.
func metricLineSpansOverlap(a, b map[string]any) bool {
	spansA := parseMetricSpanRanges(a["source_line_spans"])
	spansB := parseMetricSpanRanges(b["source_line_spans"])
	for _, ra := range spansA {
		for _, rb := range spansB {
			if ra.start <= rb.end && rb.start <= ra.end {
				return true
			}
		}
	}
	return false
}

type metricSpanRange struct{ start, end int }

// parseMetricSpanRanges reuses normalizeSourceLineSpans's canonical string
// output ("N" or "N:M") and reparses it into comparable [start,end] ranges.
func parseMetricSpanRanges(value any) []metricSpanRange {
	canonical := normalizeSourceLineSpans(value)
	out := make([]metricSpanRange, 0, len(canonical))
	for _, s := range canonical {
		start, end, ok := parseMetricLineSpan(s)
		if ok {
			out = append(out, metricSpanRange{start, end})
		}
	}
	return out
}

// computeMetricGroups partitions metrics into connected components (DR2
// "Metric Groups"): two metrics are in the same group if they directly share
// a line, or transitively via a chain of shared-line metrics. Returns groups
// as slices of indices into metrics. Union-find with path compression.
func computeMetricGroups(metrics []map[string]any) [][]int {
	n := len(metrics)
	parent := make([]int, n)
	for i := range parent {
		parent[i] = i
	}
	var find func(int) int
	find = func(x int) int {
		if parent[x] != x {
			parent[x] = find(parent[x])
		}
		return parent[x]
	}
	union := func(x, y int) {
		rx, ry := find(x), find(y)
		if rx != ry {
			parent[rx] = ry
		}
	}

	for i := 0; i < n; i++ {
		for j := i + 1; j < n; j++ {
			if metricLineSpansOverlap(metrics[i], metrics[j]) {
				union(i, j)
			}
		}
	}

	groupsByRoot := map[int][]int{}
	order := make([]int, 0, n)
	for i := 0; i < n; i++ {
		root := find(i)
		if _, ok := groupsByRoot[root]; !ok {
			order = append(order, root)
		}
		groupsByRoot[root] = append(groupsByRoot[root], i)
	}
	out := make([][]int, 0, len(order))
	for _, root := range order {
		out = append(out, groupsByRoot[root])
	}
	return out
}
```

`parseMetricLineSpan` already exists (used by `normalizeSourceLineSpans`, confirmed at `extract-metrics.go` — reused here, not redefined).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run 'TestMetricsIdentical|TestMetricLineSpansOverlap|TestComputeMetricGroups' -v`
Expected: PASS (all 5 tests)

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(metrics): add Metric Groups transitive closure and Rule-1 identity check"
```

---

### Task 6: `metrics_merge.go` — `nextMetricSeqno` counter (DR3)

**Files:**
- Modify: `server/api/doc-processing/metrics_merge.go`
- Test: `server/api/doc-processing/metrics_merge_test.go`

**Interfaces:**
- Produces: `newMetricSeqnoCounter(existing []map[string]any) *metricSeqnoCounter`, `(*metricSeqnoCounter).Assign(recordID int64) string`.
- Consumed by: Task 7 (`mergeMetrics`), Task 9 (Merge Resolution LLM call pre-assignment).

- [ ] **Step 1: Write the failing test**

Add to `metrics_merge_test.go`:

```go
func TestMetricSeqnoCounter_StartsAfterMax(t *testing.T) {
	existing := []map[string]any{
		{"metric_id": "173_mtc_2"},
		{"metric_id": "173_mtc_5"},
		{"metric_id": "173_mtc_1"},
	}
	c := newMetricSeqnoCounter(existing)
	if got := c.Assign(173); got != "173_mtc_6" {
		t.Fatalf("first assign = %q, want 173_mtc_6", got)
	}
	if got := c.Assign(173); got != "173_mtc_7" {
		t.Fatalf("second assign = %q, want 173_mtc_7", got)
	}
}

func TestMetricSeqnoCounter_EmptyExistingStartsAtOne(t *testing.T) {
	c := newMetricSeqnoCounter(nil)
	if got := c.Assign(9); got != "9_mtc_1" {
		t.Fatalf("assign = %q, want 9_mtc_1", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run TestMetricSeqnoCounter -v`
Expected: FAIL — undefined `newMetricSeqnoCounter`

- [ ] **Step 3: Implement**

Add to `metrics_merge.go`:

```go
type metricSeqnoCounter struct {
	next int
}

// newMetricSeqnoCounter scans existing metric_ids of the form "<id>_mtc_<seqno>"
// and initializes the counter to one past the current max (DR3).
func newMetricSeqnoCounter(existing []map[string]any) *metricSeqnoCounter {
	max := 0
	for _, m := range existing {
		id := asString(m["metric_id"])
		parts := strings.Split(id, "_mtc_")
		if len(parts) != 2 {
			continue
		}
		n, err := strconv.Atoi(parts[1])
		if err != nil {
			continue
		}
		if n > max {
			max = n
		}
	}
	return &metricSeqnoCounter{next: max + 1}
}

// Assign returns the next metric_id for recordID and advances the counter.
func (c *metricSeqnoCounter) Assign(recordID int64) string {
	id := fmt.Sprintf("%d_mtc_%d", recordID, c.next)
	c.next++
	return id
}
```

Add `"strconv"` and `"fmt"` to `metrics_merge.go`'s imports.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run TestMetricSeqnoCounter -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(metrics): add DR3 metric_id seqno counter"
```

---

### Task 7: `metrics_merge.go` — `mergeMetrics` (Rule-2/3/4)

**Files:**
- Modify: `server/api/doc-processing/metrics_merge.go`
- Test: `server/api/doc-processing/metrics_merge_test.go`

**Interfaces:**
- Produces: `mergeMetrics(existing, newCandidates []map[string]any, seqno *metricSeqnoCounter, recordID int64) mergeMetricsResult`, where:
  ```go
  type mergeMetricsResult struct {
  	Added         []map[string]any   // Rule-3: brand-new metrics, metric_id already assigned
  	PendingGroups [][]map[string]any // Rule-4: groups needing LLM resolution; each entry already
  	                                  // carries "metric_id" and "_merge_source" ("existing"|"new")
  }
  ```
- Consumed by: Task 8 (`FinalizeChunkBatch`).

- [ ] **Step 1: Write the failing tests**

Add to `metrics_merge_test.go`:

```go
func TestMergeMetrics_Rule2_ExactDuplicateDiscarded(t *testing.T) {
	existing := []map[string]any{
		{"metric_id": "173_mtc_1", "metric_name": "Latency", "metric_subject": "gw",
			"metric_unit": "ms", "metric_value": "200", "source_line_spans": []any{float64(2)}},
	}
	newCandidates := []map[string]any{
		{"metric_name": "Latency", "metric_subject": "gw",
			"metric_unit": "ms", "metric_value": "200", "source_line_spans": []any{float64(2)}},
	}
	res := mergeMetrics(existing, newCandidates, newMetricSeqnoCounter(existing), 173)
	if len(res.Added) != 0 {
		t.Fatalf("Added=%d, want 0 (exact duplicate should be discarded)", len(res.Added))
	}
	if len(res.PendingGroups) != 0 {
		t.Fatalf("PendingGroups=%d, want 0", len(res.PendingGroups))
	}
}

func TestMergeMetrics_Rule3_NoOverlapAdded(t *testing.T) {
	existing := []map[string]any{
		{"metric_id": "173_mtc_1", "metric_name": "Latency", "source_line_spans": []any{float64(2)}},
	}
	newCandidates := []map[string]any{
		{"metric_name": "Throughput", "source_line_spans": []any{float64(50)}},
	}
	res := mergeMetrics(existing, newCandidates, newMetricSeqnoCounter(existing), 173)
	if len(res.Added) != 1 {
		t.Fatalf("Added=%d, want 1", len(res.Added))
	}
	if res.Added[0]["metric_id"] != "173_mtc_2" {
		t.Fatalf("new metric_id=%v, want 173_mtc_2", res.Added[0]["metric_id"])
	}
	if len(res.PendingGroups) != 0 {
		t.Fatalf("PendingGroups=%d, want 0", len(res.PendingGroups))
	}
}

func TestMergeMetrics_Rule4_OverlapNotIdenticalGoesToPending(t *testing.T) {
	existing := []map[string]any{
		{"metric_id": "173_mtc_1", "metric_name": "Latency", "metric_subject": "gw",
			"metric_unit": "ms", "metric_value": "200", "source_line_spans": []any{float64(2)}},
	}
	newCandidates := []map[string]any{
		// Same line, different value -> not Rule-1 identical, but overlaps -> Rule-4.
		{"metric_name": "Latency", "metric_subject": "gw",
			"metric_unit": "ms", "metric_value": "250", "source_line_spans": []any{float64(2)}},
	}
	res := mergeMetrics(existing, newCandidates, newMetricSeqnoCounter(existing), 173)
	if len(res.Added) != 0 {
		t.Fatalf("Added=%d, want 0", len(res.Added))
	}
	if len(res.PendingGroups) != 1 || len(res.PendingGroups[0]) != 2 {
		t.Fatalf("PendingGroups=%+v, want 1 group of 2", res.PendingGroups)
	}
	var sawExisting, sawNew bool
	for _, m := range res.PendingGroups[0] {
		switch m["_merge_source"] {
		case "existing":
			sawExisting = true
			if m["metric_id"] != "173_mtc_1" {
				t.Fatalf("existing metric_id=%v, want 173_mtc_1", m["metric_id"])
			}
		case "new":
			sawNew = true
			if m["metric_id"] == nil || m["metric_id"] == "" {
				t.Fatalf("new candidate must have a pre-assigned metric_id (DR4)")
			}
		}
	}
	if !sawExisting || !sawNew {
		t.Fatalf("expected both existing and new tagged candidates in pending group")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run TestMergeMetrics -v`
Expected: FAIL — undefined `mergeMetrics`

- [ ] **Step 3: Implement**

Add to `metrics_merge.go`:

```go
type mergeMetricsResult struct {
	Added         []map[string]any
	PendingGroups [][]map[string]any
}

// mergeMetrics implements ADR 2026071002 DR2 Rule-2/3/4. existing is read
// from kb.metrics (unmodified maps); newCandidates are this run's enriched
// Pass-2 output (no metric_id yet). seqno must be initialized from existing
// (DR3) before calling.
func mergeMetrics(existing, newCandidates []map[string]any, seqno *metricSeqnoCounter, recordID int64) mergeMetricsResult {
	var result mergeMetricsResult
	remainingNew := make([]map[string]any, 0, len(newCandidates))

	// Rule-2: discard any new candidate that's an exact duplicate of an existing metric.
	for _, cand := range newCandidates {
		duplicate := false
		for _, ex := range existing {
			if metricsIdentical(cand, ex) {
				duplicate = true
				break
			}
		}
		if !duplicate {
			remainingNew = append(remainingNew, cand)
		}
	}

	// Rule-3: any remaining candidate with zero line overlap against existing
	// metrics is unambiguously new.
	stillPending := make([]map[string]any, 0, len(remainingNew))
	for _, cand := range remainingNew {
		overlapsAny := false
		for _, ex := range existing {
			if metricLineSpansOverlap(cand, ex) {
				overlapsAny = true
				break
			}
		}
		if !overlapsAny {
			added := cloneMetricMap(cand)
			added["metric_id"] = seqno.Assign(recordID)
			result.Added = append(result.Added, added)
		} else {
			stillPending = append(stillPending, cand)
		}
	}

	// Rule-4: everything left overlaps at least one existing metric. Assign a
	// metric_id to each (DR4 — every pending-list entry needs one before the
	// Merge Resolution LLM call, per DR2's updated call contract), tag its
	// source, then group by Metric Groups transitive closure over the union
	// of existing + pending candidates.
	tagged := make([]map[string]any, 0, len(existing)+len(stillPending))
	for _, ex := range existing {
		e := cloneMetricMap(ex)
		e["_merge_source"] = "existing"
		tagged = append(tagged, e)
	}
	for _, cand := range stillPending {
		c := cloneMetricMap(cand)
		c["_merge_source"] = "new"
		c["metric_id"] = seqno.Assign(recordID)
		tagged = append(tagged, c)
	}

	if len(stillPending) == 0 {
		return result
	}

	groups := computeMetricGroups(tagged)
	for _, idxs := range groups {
		hasPendingNew := false
		for _, idx := range idxs {
			if tagged[idx]["_merge_source"] == "new" {
				hasPendingNew = true
				break
			}
		}
		if !hasPendingNew {
			continue // an existing-only group with no new candidate touching it: untouched.
		}
		group := make([]map[string]any, 0, len(idxs))
		for _, idx := range idxs {
			group = append(group, tagged[idx])
		}
		result.PendingGroups = append(result.PendingGroups, group)
	}
	return result
}

func cloneMetricMap(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run TestMergeMetrics -v`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Run the whole merge test file**

Run: `cd server && go test ./api/doc-processing/ -run 'TestMetricsIdentical|TestMetricLineSpansOverlap|TestComputeMetricGroups|TestMetricSeqnoCounter|TestMergeMetrics' -v`
Expected: PASS (all tests from Tasks 5-7)

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(metrics): implement DR2 Rule-2/3/4 merge logic"
```

---

### Task 8: Prompt file for Merge Resolution LLM call

**Files:**
- Create: `prompts/prompt-merge-resolve-metrics-v1.md`

**Interfaces:**
- Consumed by: Task 9 (`loadProductPromptFromEnvKeys` default ref).

- [ ] **Step 1: Create the prompt file**

Create `prompts/prompt-merge-resolve-metrics-v1.md` (content matches the ADR's drafted prompt, `2026071002-adr-doc-processor-incremental.md` DR2 § "Merge Resolution LLM Call"):

```markdown
You resolve ambiguous metric duplicates for a document metrics database.
You are given a list of metric candidates extracted from the same input
document. Every candidate in the list shares at least one source line with
another candidate in the list (directly or through a chain of shared lines).
Some of these candidates describe the exact same real-world metric — for
example, the same measurement extracted twice by an earlier pass, or
re-extracted with minor wording differences on a later run. Others are
genuinely distinct metrics that happen to share a line, such as two
different measurements reported in the same table row.

For each candidate, decide which other candidates (if any) describe the same
metric. Group candidates that describe the same metric together. A candidate
that describes a distinct metric from all others forms its own group of one.

Do not merge two candidates only because they share a line — merge them only
if they describe the same underlying metric (same subject, same measured
value or threshold, same unit, same intent). When in doubt, prefer keeping
candidates separate (favor precision over recall: a false merge silently
discards a real metric, while a missed merge just leaves a near-duplicate for
the next run to reconsider).

When merging a group, prefer field values from the candidate tagged
"source": "existing" when it is present and its values are still supported
by the source lines; otherwise use the newly extracted candidate's values.

Input record id: {{input_record_id}}
Candidates: {{candidates_json}}

Respond with JSON only, matching this schema:
{
  "winning_metrics": [
    {
      "metric_id": "string",
      "absorbed_metric_ids": ["string"],
      "metric_name": "string",
      "metric_subject": "string",
      "metric_unit": "string",
      "metric_value": "string",
      "value_data_type": "string",
      "value_range_type": "string",
      "value_class": "string",
      "threshold_or_target": "string",
      "metric_categories": ["string"],
      "source_line_spans": ["string"]
    }
  ]
}

Rules:
- Every input metric_id must appear exactly once across the output: either
  as a winning entry's own metric_id, or inside some winning entry's
  absorbed_metric_ids.
- A candidate that is a distinct metric from all others is its own winning
  entry, with absorbed_metric_ids: [] and its fields echoed verbatim.
- When multiple input candidates describe the same metric, they collapse
  into one winning entry: metric_id is the ID of whichever absorbed
  candidate had "source": "existing" (lowest-seqno if more than one existing
  candidate is absorbed); absorbed_metric_ids lists every other input
  metric_id that was folded in. If no absorbed candidate was
  "source": "existing", metric_id is the lowest-seqno "new" ID among them.
- source_line_spans for a winning entry that absorbed others is the union of
  all absorbed candidates' spans.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "feat(prompts): add merge-resolve-metrics prompt v1"
```

---

### Task 9: `metrics_merge_resolve.go` — Merge Resolution LLM call, model/prompt wiring

**Files:**
- Create: `server/api/doc-processing/metrics_merge_resolve.go`
- Modify: `server/api/doc-processing/extract-metrics.go` (struct fields on `MetricsProcessor`, `NewMetricsProcessor`)
- Test: `server/api/doc-processing/metrics_merge_resolve_test.go`

**Interfaces:**
- Produces: `(p *MetricsProcessor) resolveMergeAmbiguities(ctx context.Context, recordID int64, group []map[string]any) ([]map[string]any, error)` — returns the winning metrics for one pending group (already validated: every input `metric_id` accounted for exactly once), or an error if both primary and fallback models fail or return an invalid partition.
- New `MetricsProcessor` fields: `MergeResolvePromptText/Ref/Path/Err`, `MergeResolveModelRef/CfgPath/Err/Name/Cfg`, `FallbackMergeResolveModelRef/CfgPath/Err/Name/Cfg` (mirrors `Mention*`/`FallbackMention*` fields exactly).
- Consumed by: Task 10 (`FinalizeChunkBatch`).

- [ ] **Step 1: Write the failing tests**

Create `server/api/doc-processing/metrics_merge_resolve_test.go`:

```go
package docprocessing

import (
	"context"
	"testing"
)

func TestResolveMergeAmbiguities_WellFormedResponse(t *testing.T) {
	extractor := &fakeJSONExtractor{outs: []map[string]any{
		{
			"winning_metrics": []any{
				map[string]any{
					"metric_id":           "173_mtc_1",
					"absorbed_metric_ids": []any{"173_mtc_9"},
					"metric_name":         "Latency", "metric_subject": "gw", "metric_unit": "ms",
					"metric_value": "250", "source_line_spans": []any{"2"},
				},
			},
		},
	}}
	p := newTestMergeResolveProcessor(t, extractor)
	group := []map[string]any{
		{"metric_id": "173_mtc_1", "_merge_source": "existing", "metric_name": "Latency"},
		{"metric_id": "173_mtc_9", "_merge_source": "new", "metric_name": "Latency"},
	}
	winners, err := p.resolveMergeAmbiguities(context.Background(), 173, group)
	if err != nil {
		t.Fatalf("resolveMergeAmbiguities: %v", err)
	}
	if len(winners) != 1 || winners[0]["metric_id"] != "173_mtc_1" {
		t.Fatalf("winners=%+v", winners)
	}
}

func TestResolveMergeAmbiguities_MissingMetricIDFailsAndUsesFallback(t *testing.T) {
	extractor := &fakeJSONExtractor{outs: []map[string]any{
		// Primary call: missing "173_mtc_9" from the output entirely -> invalid.
		{"winning_metrics": []any{
			map[string]any{"metric_id": "173_mtc_1", "absorbed_metric_ids": []any{}, "metric_name": "Latency"},
		}},
		// Fallback call: valid.
		{"winning_metrics": []any{
			map[string]any{"metric_id": "173_mtc_1", "absorbed_metric_ids": []any{"173_mtc_9"}, "metric_name": "Latency"},
		}},
	}}
	p := newTestMergeResolveProcessor(t, extractor)
	p.FallbackMergeResolveModelName = "fallback-model"
	group := []map[string]any{
		{"metric_id": "173_mtc_1", "_merge_source": "existing", "metric_name": "Latency"},
		{"metric_id": "173_mtc_9", "_merge_source": "new", "metric_name": "Latency"},
	}
	winners, err := p.resolveMergeAmbiguities(context.Background(), 173, group)
	if err != nil {
		t.Fatalf("resolveMergeAmbiguities: %v", err)
	}
	if len(winners) != 1 {
		t.Fatalf("winners=%+v, want 1 (from fallback)", winners)
	}
}

// newTestMergeResolveProcessor builds a minimal *MetricsProcessor with just
// enough wiring for resolveMergeAmbiguities, reusing the package's existing
// fakeJSONExtractor test double.
func newTestMergeResolveProcessor(t *testing.T, extractor *fakeJSONExtractor) *MetricsProcessor {
	t.Helper()
	return &MetricsProcessor{
		Extractor:              extractor,
		Logger:                 testLogger(),
		MergeResolvePromptText: "resolve merge ambiguities",
		MergeResolvePromptRef:  "prompt-merge-resolve-metrics-v1.md",
		MergeResolveModelName:  "test-merge-model",
	}
}
```

*(If `testLogger()` doesn't already exist as a test helper in the package, check `extract-metrics_test.go`/`extract-provisions_test.go` for whatever helper other tests use to build a no-op `ApiTypes.JimoLogger` — reuse that instead of inventing a new one.)*

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run TestResolveMergeAmbiguities -v`
Expected: FAIL — undefined `resolveMergeAmbiguities`, undefined struct fields

- [ ] **Step 3: Add struct fields to `MetricsProcessor`**

In `extract-metrics.go`, add to the struct (after the existing `FallbackMentionModelCfg` field, ~line 48):

```go
	MergeResolvePromptText            string
	MergeResolvePromptRef             string
	MergeResolvePromptPath            string
	MergeResolvePromptErr             error
	MergeResolveModelRef              string
	MergeResolveModelCfgPath          string
	MergeResolveModelErr              error
	MergeResolveModelName             string
	MergeResolveModelCfg              structureModelConfig
	FallbackMergeResolveModelRef      string
	FallbackMergeResolveModelCfgPath  string
	FallbackMergeResolveModelErr      error
	FallbackMergeResolveModelName     string
	FallbackMergeResolveModelCfg      structureModelConfig
```

- [ ] **Step 4: Wire env vars in `NewMetricsProcessor`**

In `NewMetricsProcessor` (`extract-metrics.go:194` area), after the existing `relationModelRef, ...` block:

```go
	mergeResolvePromptText, mergeResolvePromptRef, mergeResolvePromptPath, mergeResolvePromptErr := loadProductPromptFromEnvKeys(
		[]string{"METRIC_MERGE_RESOLVE_PROMPT"},
		"prompt-merge-resolve-metrics-v1.md",
	)
	mergeResolveModelRef, mergeResolveModelCfgPath, mergeResolveModelCfg, mergeResolveModelErr := loadModelConfigFromEnvKeys(
		[]string{"METRIC_MERGE_RESOLVE_MODEL_NAME"},
		"MODEL_DEF_FILE",
	)
	fallbackMergeResolveModelRef, fallbackMergeResolveModelCfgPath, fallbackMergeResolveModelCfg, fallbackMergeResolveModelErr := loadOptionalModelConfigFromEnv(
		"METRIC_MERGE_RESOLVE_MODEL_FALLBACK",
		"MODEL_DEF_FILE",
	)
```

And thread the results into the returned `&MetricsProcessor{...}` literal alongside the existing `Mention*`/`Fallback*` field assignments (same pattern, just the new field names from Step 3).

- [ ] **Step 5: Implement `resolveMergeAmbiguities`**

Create `server/api/doc-processing/metrics_merge_resolve.go`:

```go
package docprocessing

import (
	"context"
	"fmt"
	"strings"
)

// resolveMergeAmbiguities sends one pending Metric Group (DR2 Rule-4) to the
// Merge Resolution LLM call and returns the winning metrics. Every entry in
// group must already carry "metric_id" and "_merge_source" ("existing"|"new")
// (DR4). Retries once with the fallback model on failure or an invalid
// partition (ADR 2026071002 DR2/DR4).
func (p *MetricsProcessor) resolveMergeAmbiguities(ctx context.Context, recordID int64, group []map[string]any) ([]map[string]any, error) {
	inputIDs := make(map[string]bool, len(group))
	candidates := make([]map[string]any, 0, len(group))
	for _, m := range group {
		id := asString(m["metric_id"])
		inputIDs[id] = true
		candidates = append(candidates, map[string]any{
			"metric_id":           id,
			"source":              m["_merge_source"],
			"metric_name":         m["metric_name"],
			"metric_subject":      m["metric_subject"],
			"metric_unit":         m["metric_unit"],
			"metric_value":        m["metric_value"],
			"value_data_type":     m["value_data_type"],
			"value_range_type":    m["value_range_type"],
			"value_class":         m["value_class"],
			"threshold_or_target": m["threshold_or_target"],
			"metric_categories":   m["metric_categories"],
			"source_line_spans":   m["source_line_spans"],
		})
	}

	winners, err := p.callMergeResolve(ctx, recordID, candidates, p.MergeResolveModelName, p.MergeResolveModelCfg)
	if err == nil {
		if valErr := validateMergeResolveWinners(winners, inputIDs); valErr == nil {
			return winners, nil
		} else {
			err = valErr
		}
	}

	fallbackModelName := strings.TrimSpace(p.FallbackMergeResolveModelName)
	if fallbackModelName == "" {
		return nil, fmt.Errorf("(MID_26071101) merge resolve failed and no fallback model configured: %w", err)
	}
	if p.FallbackMergeResolveModelErr != nil {
		return nil, fmt.Errorf("(MID_26071102) merge resolve failed and fallback model %q unavailable: %w", p.FallbackMergeResolveModelRef, err)
	}
	p.Logger.Warn("merge resolve failed on primary model; retrying fallback",
		"record_id", recordID, "primary_model", p.MergeResolveModelName,
		"fallback_model", fallbackModelName, "error", err)

	winners, fbErr := p.callMergeResolve(ctx, recordID, candidates, fallbackModelName, p.FallbackMergeResolveModelCfg)
	if fbErr != nil {
		return nil, fmt.Errorf("(MID_26071103) primary merge resolve failed: %w; fallback failed: %v", err, fbErr)
	}
	if valErr := validateMergeResolveWinners(winners, inputIDs); valErr != nil {
		return nil, fmt.Errorf("(MID_26071104) fallback merge resolve returned invalid partition: %w", valErr)
	}
	return winners, nil
}

func (p *MetricsProcessor) callMergeResolve(ctx context.Context, recordID int64, candidates []map[string]any, modelName string, cfg structureModelConfig) ([]map[string]any, error) {
	applyStructureModelConfigToExtractor(p.Extractor, cfg)
	taskPrompt := mergeResolveTask(p.MergeResolvePromptText, recordID, candidates)
	in := newLLMJSONInput(ctx, p.MergeResolvePromptRef, p.MergeResolvePromptText, modelName, taskPrompt,
		"merge_resolve_metrics", "MID-26071105")
	payload, err := p.Extractor.ExtractJSON(ctx, in)
	if err != nil {
		return nil, fmt.Errorf("(MID_26071106) merge resolve LLM call failed: %w", err)
	}
	raw, ok := payload["winning_metrics"].([]any)
	if !ok {
		return nil, fmt.Errorf("(MID_26071107) merge resolve output missing winning_metrics")
	}
	winners := make([]map[string]any, 0, len(raw))
	for _, item := range raw {
		if m, ok := item.(map[string]any); ok {
			winners = append(winners, m)
		}
	}
	return winners, nil
}

// validateMergeResolveWinners checks every input metric_id appears exactly
// once, either as a winner's own metric_id or in its absorbed_metric_ids.
func validateMergeResolveWinners(winners []map[string]any, inputIDs map[string]bool) error {
	seen := map[string]int{}
	for _, w := range winners {
		id := asString(w["metric_id"])
		seen[id]++
		if absorbed, ok := w["absorbed_metric_ids"].([]any); ok {
			for _, a := range absorbed {
				seen[asString(a)]++
			}
		}
	}
	for id := range inputIDs {
		if seen[id] != 1 {
			return fmt.Errorf("(MID_26071108) metric_id %q appeared %d times in output, want 1", id, seen[id])
		}
	}
	for id := range seen {
		if !inputIDs[id] {
			return fmt.Errorf("(MID_26071109) output metric_id %q was not in the input", id)
		}
	}
	return nil
}
```

*(`mergeResolveTask` is a small helper — mirror `metricCandidateTask`'s shape at `extract-metrics.go:951`, substituting the record ID and JSON-marshaled candidates into the prompt template placeholders `{{input_record_id}}`/`{{candidates_json}}`. Add it to the same new file.)*

```go
func mergeResolveTask(basePrompt string, recordID int64, candidates []map[string]any) string {
	candidatesJSON, _ := json.Marshal(candidates)
	task := strings.ReplaceAll(basePrompt, "{{input_record_id}}", fmt.Sprintf("%d", recordID))
	return strings.ReplaceAll(task, "{{candidates_json}}", string(candidatesJSON))
}
```

(Add `"encoding/json"` to the file's imports.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run TestResolveMergeAmbiguities -v`
Expected: PASS (both tests)

- [ ] **Step 7: Build the whole package**

Run: `cd server && go build ./...`
Expected: clean build (confirms `NewMetricsProcessor`'s new field wiring compiles)

- [ ] **Step 8: Commit**

```bash
jj commit -m "feat(metrics): implement Merge Resolution LLM call with fallback (DR2/DR4)"
```

---

### Task 10: Wire DR1 skip/wipe/merge branch into `InitChunkBatch`/`ProcessChunk`

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go:2562-2634` (`InitChunkBatch`, `ProcessChunk`)
- Test: `server/api/doc-processing/extract-metrics_test.go`

**Interfaces:**
- New `MetricsProcessor` fields: `batchSkip bool`, `batchForceClear bool`, `batchExistingMetrics []map[string]any`.
- Consumes: `docProcessorFlagsFromContext` (Task 2), `MetricsStore.MetricsExist`/`GetMetricsByInputRecordID` (Task 4).

- [ ] **Step 1: Write the failing tests**

Add to `extract-metrics_test.go`:

```go
func TestMetricsProcessor_InitChunkBatch_SkipsWhenExistsAndNotForced(t *testing.T) {
	metricsStore := &fakeMetricsStore{exists: true}
	p := NewMetricsProcessor(&fakeDocMetadataStore{}, metricsStore, &fakeJSONExtractor{}, nil)
	ctx := withDocProcessorFlags(context.Background(), false, false)
	if err := p.InitChunkBatch(ctx, 173, nil, ""); err != nil {
		t.Fatalf("InitChunkBatch: %v", err)
	}
	if !p.batchSkip {
		t.Fatalf("expected batchSkip=true when force=false and metrics already exist")
	}
	if metricsStore.metricsExistCalls != 1 {
		t.Fatalf("metricsExistCalls=%d, want 1", metricsStore.metricsExistCalls)
	}
}

func TestMetricsProcessor_InitChunkBatch_ForceClearLoadsNoExisting(t *testing.T) {
	metricsStore := &fakeMetricsStore{existingMetrics: []map[string]any{{"metric_id": "173_mtc_1"}}}
	p := NewMetricsProcessor(&fakeDocMetadataStore{}, metricsStore, &fakeJSONExtractor{}, nil)
	ctx := withDocProcessorFlags(context.Background(), true, true) // force=true, force_clear=true -> wipe
	if err := p.InitChunkBatch(ctx, 173, nil, ""); err != nil {
		t.Fatalf("InitChunkBatch: %v", err)
	}
	if p.batchSkip {
		t.Fatalf("expected no skip on wipe mode")
	}
	if !p.batchForceClear {
		t.Fatalf("expected batchForceClear=true")
	}
	if len(p.batchExistingMetrics) != 0 {
		t.Fatalf("wipe mode must not load existing metrics into the merge path, got %d", len(p.batchExistingMetrics))
	}
}

func TestMetricsProcessor_InitChunkBatch_MergeModeLoadsExisting(t *testing.T) {
	metricsStore := &fakeMetricsStore{existingMetrics: []map[string]any{{"metric_id": "173_mtc_1"}}}
	p := NewMetricsProcessor(&fakeDocMetadataStore{}, metricsStore, &fakeJSONExtractor{}, nil)
	ctx := withDocProcessorFlags(context.Background(), true, false) // force=true, force_clear=false -> merge
	if err := p.InitChunkBatch(ctx, 173, nil, ""); err != nil {
		t.Fatalf("InitChunkBatch: %v", err)
	}
	if len(p.batchExistingMetrics) != 1 {
		t.Fatalf("expected existing metrics loaded for merge mode, got %d", len(p.batchExistingMetrics))
	}
}

func TestMetricsProcessor_ProcessChunk_NoOpWhenSkipping(t *testing.T) {
	extractor := &fakeJSONExtractor{}
	p := NewMetricsProcessor(&fakeDocMetadataStore{}, &fakeMetricsStore{exists: true}, extractor, nil)
	ctx := withDocProcessorFlags(context.Background(), false, false)
	if err := p.InitChunkBatch(ctx, 173, []Chunk{{Index: 0}}, ""); err != nil {
		t.Fatalf("InitChunkBatch: %v", err)
	}
	if err := p.ProcessChunk(ctx, 0); err != nil {
		t.Fatalf("ProcessChunk: %v", err)
	}
	if extractor.structuredCalledCount != 0 || extractor.calledCount != 0 {
		t.Fatalf("expected zero LLM calls when skipping, got structured=%d plain=%d",
			extractor.structuredCalledCount, extractor.calledCount)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run 'TestMetricsProcessor_InitChunkBatch|TestMetricsProcessor_ProcessChunk_NoOp' -v`
Expected: FAIL — `p.batchSkip undefined`

- [ ] **Step 3: Add fields and implement**

Add fields to `MetricsProcessor` struct (alongside the existing `batch*` fields, ~line 70-79):

```go
	batchSkip            bool
	batchForceClear      bool
	batchExistingMetrics []map[string]any
```

Replace `InitChunkBatch` (lines 2562-2578):

```go
func (p *MetricsProcessor) InitChunkBatch(ctx context.Context, recordID int64, chunks []Chunk, docCtx string) error {
	if p.MentionPromptErr != nil {
		return fmt.Errorf("(MID_26062750) %s candidate prompt error: %w", p.Name(), p.MentionPromptErr)
	}
	if p.ModelErr != nil {
		p.Logger.Warn("%s skipped: model config error", p.Name(), "record_id", recordID, "error", p.ModelErr)
		return nil
	}

	force, forceClear := docProcessorFlagsFromContext(ctx)
	p.batchForceClear = forceClear
	p.batchSkip = false
	p.batchExistingMetrics = nil

	if !force {
		exists, err := p.Store.MetricsExist(ctx, recordID)
		if err != nil {
			return fmt.Errorf("(MID_26071110) %s check metrics exist: %w", p.Name(), err)
		}
		if exists {
			p.Logger.Info("metrics extraction skipped", "record_id", recordID, "reason", "metrics already exist and force=false")
			p.batchSkip = true
			return nil
		}
	}

	if !forceClear {
		existing, err := p.Store.GetMetricsByInputRecordID(ctx, recordID)
		if err != nil {
			return fmt.Errorf("(MID_26071111) %s load existing metrics: %w", p.Name(), err)
		}
		p.batchExistingMetrics = existing
	}

	p.batchStart = p.Now()
	p.batchRecordID = recordID
	p.batchChunks = chunks
	p.batchDocCtx = docCtx
	p.batchMentions = nil
	p.batchLang = "unknown"
	p.batchModelName = strings.TrimSpace(p.MentionModelName)
	return nil
}
```

At the top of `ProcessChunk` (line 2580), add the skip guard as the very first check:

```go
func (p *MetricsProcessor) ProcessChunk(ctx context.Context, chunkIdx int) error {
	if p.batchSkip {
		return nil
	}
	if chunkIdx < 0 || chunkIdx >= len(p.batchChunks) {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run 'TestMetricsProcessor_InitChunkBatch|TestMetricsProcessor_ProcessChunk_NoOp' -v`
Expected: PASS (all 4 tests)

- [ ] **Step 5: Run the full existing test file to check for regressions**

Run: `cd server && go test ./api/doc-processing/ -run TestMetricsProcessor -v 2>&1 | tail -60`
Expected: PASS, no regressions in existing `HandleEvent`-based tests (untouched)

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(metrics): wire DR1 skip/wipe/merge branch into InitChunkBatch/ProcessChunk"
```

---

### Task 11: Wire DR2/DR3/DR4 merge + dirty-check persistence into `FinalizeChunkBatch`

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go:2636-2675` (`FinalizeChunkBatch`)
- Test: `server/api/doc-processing/extract-metrics_test.go`

**Interfaces:**
- Consumes: `mergeMetrics`, `newMetricSeqnoCounter`, `(*MetricsProcessor).resolveMergeAmbiguities`, `MetricsStore.UpsertMetrics`, `MetricsStore.DeleteMetricsByInputRecordID`, `MetricsStore.SaveMetrics` (wipe path, unchanged).

**Plan gap discovered during Task 9's review, fixed here:** ADR 2026071002 DR2 requires the Merge Resolution LLM call to run with `ThinkingType = "disabled"` for determinism, the same as the existing extraction passes. The existing extraction passes achieve this via `(p *MetricsProcessor) forceDisableThinking()` (`extract-metrics.go:589-593`), which is called unconditionally at the end of `NewMetricsProcessor` (not just from the legacy `HandleEvent` path) and currently force-disables `MentionModelCfg`, `FallbackMentionModelCfg`, and `RelationModelCfg` only. Task 9 added `MergeResolveModelCfg`/`FallbackMergeResolveModelCfg` but did not add them to this method (correctly out of Task 9's scope — this method wasn't mentioned in that task's brief). This task must extend it:

- [ ] **Step 0: Extend `forceDisableThinking` to cover the merge-resolve model configs**

In `extract-metrics.go`, change:

```go
func (p *MetricsProcessor) forceDisableThinking() {
	p.MentionModelCfg = forceDisableThinking(p.MentionModelCfg)
	p.FallbackMentionModelCfg = forceDisableThinking(p.FallbackMentionModelCfg)
	p.RelationModelCfg = forceDisableThinking(p.RelationModelCfg)
}
```

to:

```go
func (p *MetricsProcessor) forceDisableThinking() {
	p.MentionModelCfg = forceDisableThinking(p.MentionModelCfg)
	p.FallbackMentionModelCfg = forceDisableThinking(p.FallbackMentionModelCfg)
	p.RelationModelCfg = forceDisableThinking(p.RelationModelCfg)
	p.MergeResolveModelCfg = forceDisableThinking(p.MergeResolveModelCfg)
	p.FallbackMergeResolveModelCfg = forceDisableThinking(p.FallbackMergeResolveModelCfg)
}
```

Add a test (e.g. `TestMetricsProcessor_ForceDisablesThinkingForMergeResolveModels`) following the pattern of the existing `TestMetricsProcessor_ForceDisablesThinkingForAllPasses` test already in `extract-metrics_test.go` (construct a `MetricsProcessor` with `MergeResolveModelCfg`/`FallbackMergeResolveModelCfg` set to a `structureModelConfig{ThinkingType: "enabled"}`, call `NewMetricsProcessor` or `forceDisableThinking()` directly, assert both configs come back with `ThinkingType == "disabled"`). Run it, confirm RED before the fix, GREEN after.

- [ ] **Step 1: Write the failing tests**

Add to `extract-metrics_test.go`:

```go
func TestFinalizeChunkBatch_SkipModeIsNoOp(t *testing.T) {
	metricsStore := &fakeMetricsStore{}
	p := NewMetricsProcessor(&fakeDocMetadataStore{}, metricsStore, &fakeJSONExtractor{}, nil)
	p.batchSkip = true
	if err := p.FinalizeChunkBatch(context.Background()); err != nil {
		t.Fatalf("FinalizeChunkBatch: %v", err)
	}
	if metricsStore.saveCalled != 0 || metricsStore.upsertCalled != 0 || metricsStore.deleteCalled != 0 {
		t.Fatalf("expected zero store calls in skip mode, got save=%d upsert=%d delete=%d",
			metricsStore.saveCalled, metricsStore.upsertCalled, metricsStore.deleteCalled)
	}
}

func TestFinalizeChunkBatch_WipeModeDeletesThenSaves(t *testing.T) {
	metricsStore := &fakeMetricsStore{}
	extractor := &fakeJSONExtractor{outs: []map[string]any{
		{"metrics": []any{map[string]any{"metric_name": "Latency", "source_line_spans": []any{float64(2)}}}, "uncertain_metrics": []any{}},
	}}
	p := NewMetricsProcessor(&fakeDocMetadataStore{rec: DocMetadataInputRecord{ID: 173}}, metricsStore, extractor, nil)
	p.batchRecordID = 173
	p.batchForceClear = true
	p.batchMentions = []metricCandidateMention{{MetricNameHint: "Latency", SourceLineSpans: []any{float64(2)}}}
	if err := p.FinalizeChunkBatch(context.Background()); err != nil {
		t.Fatalf("FinalizeChunkBatch: %v", err)
	}
	if metricsStore.deleteCalled != 1 {
		t.Fatalf("deleteCalled=%d, want 1 (wipe mode)", metricsStore.deleteCalled)
	}
	if metricsStore.saveCalled != 1 {
		t.Fatalf("saveCalled=%d, want 1", metricsStore.saveCalled)
	}
	if metricsStore.upsertCalled != 0 {
		t.Fatalf("upsertCalled=%d, want 0 (wipe mode uses SaveMetrics, not UpsertMetrics)", metricsStore.upsertCalled)
	}
}

func TestFinalizeChunkBatch_MergeMode_UnchangedExistingNotWritten(t *testing.T) {
	metricsStore := &fakeMetricsStore{
		existingMetrics: []map[string]any{
			{"metric_id": "173_mtc_1", "metric_name": "Latency", "metric_subject": "gw",
				"metric_unit": "ms", "metric_value": "200", "source_line_spans": []any{float64(2)}},
		},
	}
	// Extractor re-produces the *same* metric (Rule-2 exact duplicate) -> nothing dirty.
	extractor := &fakeJSONExtractor{outs: []map[string]any{
		{"metrics": []any{map[string]any{
			"metric_name": "Latency", "subject": "gw", "unit": "ms", "metric_value": "200",
			"source_line_spans": []any{float64(2)},
		}}, "uncertain_metrics": []any{}},
	}}
	p := NewMetricsProcessor(&fakeDocMetadataStore{rec: DocMetadataInputRecord{ID: 173}}, metricsStore, extractor, nil)
	p.batchRecordID = 173
	p.batchForceClear = false
	p.batchExistingMetrics = metricsStore.existingMetrics
	p.batchMentions = []metricCandidateMention{{MetricNameHint: "Latency", SourceLineSpans: []any{float64(2)}}}
	if err := p.FinalizeChunkBatch(context.Background()); err != nil {
		t.Fatalf("FinalizeChunkBatch: %v", err)
	}
	if metricsStore.deleteCalled != 0 {
		t.Fatalf("deleteCalled=%d, want 0 (merge mode never deletes)", metricsStore.deleteCalled)
	}
	if metricsStore.upsertCalled != 0 {
		t.Fatalf("upsertCalled=%d, want 0 (Rule-2 duplicate: nothing dirty, no write)", metricsStore.upsertCalled)
	}
}

func TestFinalizeChunkBatch_MergeMode_NewMetricUpserted(t *testing.T) {
	metricsStore := &fakeMetricsStore{
		existingMetrics: []map[string]any{
			{"metric_id": "173_mtc_1", "metric_name": "Latency", "source_line_spans": []any{float64(2)}},
		},
	}
	extractor := &fakeJSONExtractor{outs: []map[string]any{
		{"metrics": []any{map[string]any{
			"metric_name": "Throughput", "source_line_spans": []any{float64(50)},
		}}, "uncertain_metrics": []any{}},
	}}
	p := NewMetricsProcessor(&fakeDocMetadataStore{rec: DocMetadataInputRecord{ID: 173}}, metricsStore, extractor, nil)
	p.batchRecordID = 173
	p.batchForceClear = false
	p.batchExistingMetrics = metricsStore.existingMetrics
	p.batchMentions = []metricCandidateMention{{MetricNameHint: "Throughput", SourceLineSpans: []any{float64(50)}}}
	if err := p.FinalizeChunkBatch(context.Background()); err != nil {
		t.Fatalf("FinalizeChunkBatch: %v", err)
	}
	if metricsStore.upsertCalled != 1 {
		t.Fatalf("upsertCalled=%d, want 1", metricsStore.upsertCalled)
	}
	if len(metricsStore.lastUpsert.Metrics) != 1 || metricsStore.lastUpsert.Metrics[0]["metric_id"] != "173_mtc_2" {
		t.Fatalf("unexpected upsert payload: %+v", metricsStore.lastUpsert.Metrics)
	}
}
```

*(Check `metricCandidateMention`'s actual field names before using `MetricNameHint`/`SourceLineSpans` above — grep `type metricCandidateMention struct` at `extract-metrics.go:132` and match exactly; adjust the test literals to the real field names if they differ.)*

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run TestFinalizeChunkBatch -v`
Expected: FAIL (current `FinalizeChunkBatch` has no skip/merge branching; `deleteCalled`/`upsertCalled` assertions fail)

- [ ] **Step 3: Implement**

Replace `FinalizeChunkBatch` (lines 2636-2675):

```go
func (p *MetricsProcessor) FinalizeChunkBatch(ctx context.Context) error {
	if p.batchSkip {
		return nil
	}
	candidates := mentionsAsCandidates(p.batchMentions)
	if len(candidates) == 0 {
		p.Logger.Info("%s batch: no candidates", p.Name(), "record_id", p.batchRecordID)
		return nil
	}
	if isCtxStopped(ctx) {
		return ErrPipelineStopped
	}
	metrics, _, err := p.enrichMetricCandidates(ctx, p.batchRecordID, candidates, p.batchDocCtx)
	if err != nil {
		if errors.Is(err, ErrPipelineStopped) {
			return ErrPipelineStopped
		}
		return fmt.Errorf("(MID_26062752) %s enrich metrics: %w", p.Name(), err)
	}
	rec, err := p.InputStore.GetInputRecord(ctx, p.batchRecordID)
	if err != nil {
		return fmt.Errorf("(MID_26062753) %s load record: %w", p.Name(), err)
	}

	if p.batchForceClear {
		for i, m := range metrics {
			m["metric_id"] = fmt.Sprintf("%d_mtc_%d", p.batchRecordID, i+1)
			metrics[i] = m
		}
		_, _ = p.Store.DeleteMetricsByInputRecordID(ctx, p.batchRecordID)
		if _, err := p.Store.SaveMetrics(ctx, SaveMetricsRequest{
			InputRecordID: p.batchRecordID,
			EventID:       eventIDFromContext(ctx),
			Language:      firstNonEmptyTrimmed(p.batchLang, "unknown"),
			ModelName:     firstNonEmptyTrimmed(p.batchModelName, p.MentionModelName),
			PromptName:    p.RelationPromptRef,
			Metrics:       metrics,
		}); err != nil {
			return fmt.Errorf("(MID_26062754) %s save metrics: %w", p.Name(), err)
		}
		if fileErr := p.saveMetricsToFile(p.batchRecordID, rec, metrics); fileErr != nil {
			p.Logger.Warn("save metrics to file failed", "record_id", p.batchRecordID, "error", fileErr)
		}
		return nil
	}

	dirty, err := p.mergeAndCollectDirtyMetrics(ctx, metrics)
	if err != nil {
		return fmt.Errorf("(MID_26071112) %s merge metrics: %w", p.Name(), err)
	}
	if len(dirty) > 0 {
		if _, err := p.Store.UpsertMetrics(ctx, SaveMetricsRequest{
			InputRecordID: p.batchRecordID,
			EventID:       eventIDFromContext(ctx),
			Language:      firstNonEmptyTrimmed(p.batchLang, "unknown"),
			ModelName:     firstNonEmptyTrimmed(p.batchModelName, p.MentionModelName),
			PromptName:    p.RelationPromptRef,
			Metrics:       dirty,
		}); err != nil {
			return fmt.Errorf("(MID_26071113) %s upsert metrics: %w", p.Name(), err)
		}
	}
	if fileErr := p.saveMetricsToFile(p.batchRecordID, rec, dirty); fileErr != nil {
		p.Logger.Warn("save metrics to file failed", "record_id", p.batchRecordID, "error", fileErr)
	}
	return nil
}

// mergeAndCollectDirtyMetrics runs DR2 (Rule-2/3/4) against this run's newly
// enriched metrics and the existing metrics loaded in InitChunkBatch, resolves
// any ambiguous groups via the Merge Resolution LLM call (DR4), and returns
// only the metrics that are new or actually changed content — each already
// carrying an ext_info.merge_log entry.
func (p *MetricsProcessor) mergeAndCollectDirtyMetrics(ctx context.Context, newMetrics []map[string]any) ([]map[string]any, error) {
	seqno := newMetricSeqnoCounter(p.batchExistingMetrics)
	merged := mergeMetrics(p.batchExistingMetrics, newMetrics, seqno, p.batchRecordID)

	var dirty []map[string]any
	now := p.Now()

	for _, added := range merged.Added {
		added["ext_info"] = map[string]any{"merge_log": []map[string]any{
			{"run_time": now.Format(time.RFC3339), "action": "added"},
		}}
		dirty = append(dirty, added)
	}

	existingByID := map[string]map[string]any{}
	for _, ex := range p.batchExistingMetrics {
		existingByID[asString(ex["metric_id"])] = ex
	}

	for _, group := range merged.PendingGroups {
		winners, err := p.resolveMergeAmbiguities(ctx, p.batchRecordID, group)
		if err != nil {
			return nil, err
		}
		for _, w := range winners {
			absorbed, _ := w["absorbed_metric_ids"].([]any)
			id := asString(w["metric_id"])
			existing, wasExisting := existingByID[id]
			if len(absorbed) == 0 && wasExisting && metricContentEqual(existing, w) {
				continue // DR4 dirty-check: unchanged existing row, skip entirely.
			}
			action := "added"
			if wasExisting {
				action = "merged"
			}
			absorbedIDs := make([]string, 0, len(absorbed))
			for _, a := range absorbed {
				absorbedIDs = append(absorbedIDs, asString(a))
			}
			logEntry := map[string]any{"run_time": now.Format(time.RFC3339), "action": action}
			if len(absorbedIDs) > 0 {
				logEntry["absorbed_metric_ids"] = absorbedIDs
			}
			w["ext_info"] = map[string]any{"merge_log": []map[string]any{logEntry}}
			dirty = append(dirty, w)
		}
	}
	return dirty, nil
}

// metricContentEqual compares the fields the merge pipeline actually produces
// (DR4 dirty-check) — deliberately excludes metric_id, ext_info, and any
// internal "_merge_source" tag.
func metricContentEqual(existing, candidate map[string]any) bool {
	fields := []string{"metric_name", "metric_subject", "metric_unit", "metric_value",
		"value_data_type", "value_range_type", "value_class", "threshold_or_target"}
	for _, f := range fields {
		if strings.TrimSpace(asString(existing[f])) != strings.TrimSpace(asString(candidate[f])) {
			return false
		}
	}
	existingSpans := strings.Join(normalizeSourceLineSpans(existing["source_line_spans"]), ",")
	candidateSpans := strings.Join(normalizeSourceLineSpans(candidate["source_line_spans"]), ",")
	if existingSpans != candidateSpans {
		return false
	}
	existingCats := strings.Join(metricCategoryKeysFromValue(existing["metric_categories"]), ",")
	candidateCats := strings.Join(metricCategoryKeysFromValue(candidate["metric_categories"]), ",")
	return existingCats == candidateCats
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run TestFinalizeChunkBatch -v`
Expected: PASS (all 4 tests)

- [ ] **Step 5: Run the entire doc-processing package test suite**

Run: `cd server && go build ./... && go test ./api/doc-processing/... 2>&1 | tail -60`
Expected: builds and passes with no regressions

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(metrics): wire DR2/DR3/DR4 merge and dirty-check persistence into FinalizeChunkBatch"
```

---

### Task 12: Reconstruct Rule-4 merged-winner rows from full source data (data-loss fix)

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go` (`mergeAndCollectDirtyMetrics`, ~line 3025)
- Test: `server/api/doc-processing/extract-metrics_test.go`

**Interfaces:**
- Consumes: `group []map[string]any` (the pending-group parameter already passed to `resolveMergeAmbiguities` inside `mergeAndCollectDirtyMetrics`'s loop — each entry already carries a `metric_id` and the FULL enriched/persisted field set, per Tasks 7 and 10).
- Produces: `mergeResolveDecidedFields []string` (package-level var).

**Why this task exists:** Task 11's review (Task 11 is already merged) found a real, live-path data-loss bug that predates Task 11 itself — it originates in the Merge Resolution LLM's schema (Task 9) and this ADR's own design. The `winning_metrics` response only carries ~10 fields (`metric_name`, `metric_subject`, `metric_unit`, `metric_value`, `value_data_type`, `value_range_type`, `value_class`, `threshold_or_target`, `metric_categories`, `source_line_spans`). `mergeAndCollectDirtyMetrics` currently writes a Rule-4 "merged" winner to the DB using that sparse map directly. Since `UpsertMetrics` does `ON CONFLICT DO UPDATE SET` on every column, any Rule-4 merged row silently blanks `metric_desc`, `metric_context`, `metric_keywords`, `location_type`, `formula_or_definition`, `measurement_frequency`, `category_paths`, and all `*_en` variants — real, silent partial data loss for exactly the metrics that go through LLM-adjudicated merging (Rule-2 exact-duplicates and Rule-3 additions are unaffected, since those come from the full enriched map, not the LLM's sparse output).

**Fix:** before writing a winner, reconstruct its full row by cloning the FULL source map for that `metric_id` (already sitting in `group`, the pending-group slice `mergeAndCollectDirtyMetrics` already has in scope — no new data fetch needed) and overlay only the fields the Merge Resolution LLM actually decided on. Fields the LLM didn't touch (`desc`, `context`, `keywords`, etc.) survive from the source row.

- [ ] **Step 1: Write the failing test**

Add to `extract-metrics_test.go`:

```go
func TestMergeAndCollectDirtyMetrics_MergedWinnerPreservesUntouchedFields(t *testing.T) {
	existingRow := map[string]any{
		"metric_id": "173_mtc_1", "metric_name": "Latency", "metric_subject": "gw",
		"metric_unit": "ms", "metric_value": "200", "source_line_spans": []any{float64(2)},
		"metric_desc": "max end-to-end latency", "metric_context": "SLA section 4",
	}
	extractor := &fakeJSONExtractor{outs: []map[string]any{
		// Pass-2 enrichment output for the new candidate.
		{"metrics": []any{map[string]any{
			"metric_name": "Latency", "subject": "gw", "unit": "ms", "metric_value": "250",
			"source_line_spans": []any{float64(2)},
		}}, "uncertain_metrics": []any{}},
		// Merge Resolution LLM output: sparse, no desc/context.
		{"winning_metrics": []any{map[string]any{
			"metric_id": "173_mtc_1", "absorbed_metric_ids": []any{"173_mtc_2"},
			"metric_name": "Latency", "metric_subject": "gw", "metric_unit": "ms",
			"metric_value": "250", "source_line_spans": []any{"2"},
		}}},
	}}
	p := NewMetricsProcessor(&fakeDocMetadataStore{rec: DocMetadataInputRecord{ID: 173}}, &fakeMetricsStore{}, extractor, nil)
	p.batchRecordID = 173
	p.batchExistingMetrics = []map[string]any{existingRow}
	p.MergeResolvePromptText = "resolve"
	p.MergeResolveModelName = "test-merge-model"

	dirty, err := p.mergeAndCollectDirtyMetrics(context.Background(), []map[string]any{
		{"metric_name": "Latency", "subject": "gw", "unit": "ms", "metric_value": "250", "source_line_spans": []any{float64(2)}},
	})
	if err != nil {
		t.Fatalf("mergeAndCollectDirtyMetrics: %v", err)
	}
	if len(dirty) != 1 {
		t.Fatalf("dirty=%d, want 1", len(dirty))
	}
	if dirty[0]["metric_desc"] != "max end-to-end latency" {
		t.Fatalf("metric_desc lost in merged winner: %+v", dirty[0])
	}
	if dirty[0]["metric_context"] != "SLA section 4" {
		t.Fatalf("metric_context lost in merged winner: %+v", dirty[0])
	}
	if dirty[0]["metric_value"] != "250" {
		t.Fatalf("expected LLM-decided field metric_value=250 to win, got %v", dirty[0]["metric_value"])
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./server/api/doc-processing/ -run TestMergeAndCollectDirtyMetrics_MergedWinnerPreservesUntouchedFields -v`
Expected: FAIL — `metric_desc lost in merged winner` (the current code writes the sparse LLM winner map directly, which has no `metric_desc` key)

- [ ] **Step 3: Implement the reconstruction**

In `extract-metrics.go`, add a package-level var near `metricFieldAliasPairs`:

```go
// mergeResolveDecidedFields lists the fields the Merge Resolution LLM call's
// winning_metrics response actually returns (prompt-merge-resolve-metrics-v1.md).
// Everything else on a Rule-4 winner must come from the full source row, not
// this sparse LLM output, or those columns get silently blanked on write.
var mergeResolveDecidedFields = []string{
	"metric_name", "metric_subject", "metric_unit", "metric_value",
	"value_data_type", "value_range_type", "value_class",
	"threshold_or_target", "metric_categories", "source_line_spans",
}
```

In `mergeAndCollectDirtyMetrics`, inside the `for _, group := range merged.PendingGroups` loop, right after `winners, err := p.resolveMergeAmbiguities(...)`:

```go
	for _, group := range merged.PendingGroups {
		winners, err := p.resolveMergeAmbiguities(ctx, p.batchRecordID, group)
		if err != nil {
			return nil, err
		}
		groupByID := map[string]map[string]any{}
		for _, g := range group {
			groupByID[asString(g["metric_id"])] = g
		}
		for _, w := range winners {
			w = canonicalizeMetricFieldAliases(w)
			absorbed, _ := w["absorbed_metric_ids"].([]any)
			id := asString(w["metric_id"])
			existingRow, wasExisting := existingByID[id]
			if len(absorbed) == 0 && wasExisting && metricContentEqual(existingRow, w) {
				continue // DR4 dirty-check: unchanged existing row, skip entirely.
			}
			if full, ok := groupByID[id]; ok {
				reconstructed := cloneMetricMap(full)
				for _, f := range mergeResolveDecidedFields {
					if v, ok := w[f]; ok {
						reconstructed[f] = v
					}
				}
				reconstructed["metric_id"] = id
				w = reconstructed
			}
			action := "added"
			if wasExisting {
				action = "merged"
			}
			absorbedIDs := make([]string, 0, len(absorbed))
			for _, a := range absorbed {
				absorbedIDs = append(absorbedIDs, asString(a))
			}
			logEntry := map[string]any{"run_time": now.Format(time.RFC3339), "action": action}
			if len(absorbedIDs) > 0 {
				logEntry["absorbed_metric_ids"] = absorbedIDs
			}
			w["ext_info"] = map[string]any{"merge_log": []map[string]any{logEntry}}
			dirty = append(dirty, w)
		}
	}
```

Note: `groupByID` is keyed by every `metric_id` in the pending group — both `_merge_source: "existing"` and `_merge_source: "new"` entries carry one (per Task 7/10), so this uniformly covers a winner that was an existing row, a winner that was a brand-new candidate, or a winner that absorbed others — in every case the reconstruction starts from that winning identity's own full field set, which is the correct "whichever candidate won" semantics already implied by the ADR's merge-resolution design.

If `groupByID[id]` is somehow missing (should not happen given `validateMergeResolveWinners` already guarantees every output `metric_id` came from the input group), fall back to using `w` as-is rather than panicking — this preserves today's (sparse-but-functional) behavior for that unexpected case instead of crashing the run.

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./server/api/doc-processing/ -run TestMergeAndCollectDirtyMetrics_MergedWinnerPreservesUntouchedFields -v`
Expected: PASS

- [ ] **Step 5: Run the full `FinalizeChunkBatch`/merge test suite to confirm no regressions**

Run: `go build ./server/api/doc-processing/... && go test ./server/api/doc-processing/ -run 'TestFinalizeChunkBatch|TestMergeMetrics|TestResolveMergeAmbiguities|TestMergeAndCollectDirtyMetrics' -v`
Expected: all PASS, no regressions in the existing Task 11 tests (in particular, re-confirm `TestFinalizeChunkBatch_MergeMode_UnchangedExistingNotWritten` still passes — the dirty-check decision itself, made before reconstruction, must be unaffected by this change).

Then run the full package suite once: `go test ./server/api/doc-processing/...` — same ~20 pre-existing unrelated failures as baseline, no new ones.

- [ ] **Step 6: Commit**

```bash
git commit -m "fix(metrics): reconstruct Rule-4 merged-winner rows from full source data to prevent field blanking"
```

---

### Task 13: Restore wipe-guard parity for provisions, inventory_items, entity/relation

**Files:**
- Modify: `server/api/doc-processing/extract-provisions.go:1949-1982` (`InitChunkBatch`), `:2056` (`FinalizeChunkBatch`)
- Modify: `server/api/doc-processing/extract-inventory-items.go:2051` (`InitChunkBatch`), `:2127` (`FinalizeChunkBatch`)
- Modify: `server/api/doc-processing/entity-relation-split.go:328-393` (`EntityProcessor`/`RelationProcessor` Init/Finalize, via shared `EntityRelationProcessor.initEntityBatch`/`finalizeEntityBatch`/relation equivalents)
- Test: corresponding `_test.go` files for each

**Interfaces:**
- Consumes: `docProcessorFlagsFromContext` (Task 2). No new types produced — this task only restores today's documented `force`-gated wipe behavior (per the ADR's scope note: these three "always behave as if force_clear is true") on the coordinator path where it's currently missing (Critical Finding).

**Why this task exists:** the ADR's Code Changes section says these three processors should "accept force_clear... but always take the existing wipe branch." That wipe branch doesn't currently execute on the live coordinator path (same bug as metrics, per the Critical Finding) — so implementing this sentence faithfully requires adding the guard, not just accepting-and-ignoring a field.

- [ ] **Step 1: Write the failing test for provisions**

Add to `server/api/doc-processing/extract-provisions_test.go`:

```go
func TestProvisionsProcessor_InitChunkBatch_DeletesExistingWhenForced(t *testing.T) {
	store := &fakeProvisionsStore{} // reuse existing fake in this test file
	p := NewProvisionsProcessor(&fakeDocMetadataStore{}, store, &fakeJSONExtractor{}, nil)
	ctx := withDocProcessorFlags(context.Background(), true, true)
	if err := p.InitChunkBatch(ctx, 173, nil, ""); err != nil {
		t.Fatalf("InitChunkBatch: %v", err)
	}
	if store.deleteCalled != 1 {
		t.Fatalf("deleteCalled=%d, want 1", store.deleteCalled)
	}
}

func TestProvisionsProcessor_InitChunkBatch_SkipsWhenExistsAndNotForced(t *testing.T) {
	store := &fakeProvisionsStore{exists: true}
	p := NewProvisionsProcessor(&fakeDocMetadataStore{}, store, &fakeJSONExtractor{}, nil)
	ctx := withDocProcessorFlags(context.Background(), false, false)
	if err := p.InitChunkBatch(ctx, 173, nil, ""); err != nil {
		t.Fatalf("InitChunkBatch: %v", err)
	}
	if !p.batchSkip {
		t.Fatalf("expected batchSkip=true")
	}
}
```

*(Check the exact name of the existing provisions fake store and its `deleteCalled`/`exists` fields before writing this — grep `type fakeProvisionsStore` in `extract-provisions_test.go` and match field names exactly; adjust if they differ from the metrics fake's naming.)*

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./api/doc-processing/ -run TestProvisionsProcessor_InitChunkBatch -v`
Expected: FAIL — `p.batchSkip undefined` or delete not called

- [ ] **Step 3: Implement for provisions**

Add a `batchSkip bool` field to `ProvisionsProcessor`'s struct (alongside its existing `batch*` fields). At the top of `InitChunkBatch` (`extract-provisions.go:1949`), after the existing prompt/model/store nil checks, before `p.batchStart = p.Now()`:

```go
	force, _ := docProcessorFlagsFromContext(ctx)
	p.batchSkip = false
	if force {
		_, _ = p.Store.DeleteProvisionsByInputRecordID(ctx, recordID)
	} else {
		exists, err := p.Store.ProvisionsExist(ctx, recordID, "")
		if err != nil {
			return fmt.Errorf("(MID_26071120) %s check provisions exist: %w", p.Name(), err)
		}
		if exists {
			p.Logger.Info("provisions extraction skipped", "record_id", recordID, "reason", "provisions already exist and force=false")
			reindexExistingSearchOnSkip(ctx, searchArtifactProvision, recordID, p.Logger, ReindexProvisionSearchForRecord)
			p.batchSkip = true
			return nil
		}
	}
```

At the top of `ProcessChunk` (`extract-provisions.go:1987`), add the same guard as Task 10 Step 3:

```go
func (p *ProvisionsProcessor) ProcessChunk(ctx context.Context, chunkIdx int) error {
	if p.batchSkip {
		return nil
	}
```

At the top of `FinalizeChunkBatch` (`extract-provisions.go:2056`):

```go
func (p *ProvisionsProcessor) FinalizeChunkBatch(ctx context.Context) error {
	if p.batchSkip {
		return nil
	}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd server && go test ./api/doc-processing/ -run TestProvisionsProcessor_InitChunkBatch -v`
Expected: PASS

- [ ] **Step 5: Repeat Steps 1-4 for `InventoryItemsProcessor`**

Same pattern: `docProcessorFlagsFromContext`, `force ? (DeleteInventoryItemsByInputRecordID + DeleteInventoryItemDuplicatesByInputRecordID) : (InventoryItemsExist check + reindexExistingSearchOnSkip + batchSkip=true)`, applied at `extract-inventory-items.go:2051` (`InitChunkBatch`), `:2067` (`ProcessChunk` guard), `:2127` (`FinalizeChunkBatch` guard). Mirror the exact existing `HandleEvent` block shown in the ADR's research (delete both tables, or check `InventoryItemsExist`). Write the two equivalent tests in `extract-inventory-items_test.go` first (TDD), confirm failure, implement, confirm pass.

Run: `cd server && go test ./api/doc-processing/ -run TestInventoryItemsProcessor_InitChunkBatch -v`
Expected: PASS

- [ ] **Step 6: Repeat for `EntityProcessor`/`RelationProcessor`**

These delegate to shared methods `EntityRelationProcessor.initEntityBatch`/`finalizeEntityBatch` (entity) and `RelationProcessor`'s own `InitChunkBatch`/`FinalizeChunkBatch` (relation) in `entity-relation-split.go:328-393`. Add the same `force`-gated guard to `initEntityBatch` (checking `EntitiesExist`/`DeleteEntitiesByInputRecordID`) and to `RelationProcessor.InitChunkBatch` (checking `RelationsExist`/`DeleteRelationsByInputRecordID`), plus the `batchSkip` no-op guard in both processors' `ProcessChunk`/`FinalizeChunkBatch`. Write tests in whatever test file covers `entity-relation-split.go` first (check for `entity-relation-split_test.go` or similar; if none exists, add to `extract-entity-relation_test.go`), confirm failure, implement, confirm pass.

Run: `cd server && go test ./api/doc-processing/ -run 'TestEntityProcessor|TestRelationProcessor' -v`
Expected: PASS

- [ ] **Step 7: Full package regression check**

Run: `cd server && go build ./... && go test ./api/doc-processing/... 2>&1 | tail -80`
Expected: clean build, all tests pass

- [ ] **Step 8: Commit**

```bash
jj commit -m "fix(doc-processing): restore force-gated wipe guard on the chunk-batch path for provisions/inventory_items/entity_relation"
```

---

### Task 14: Frontend `force_clear` control

**Files:**
- Modify: `web/src/lib/components/home3/doc-processor-dashboard-view.svelte`

**Interfaces:**
- New component-local state: `forceClear = $state(false)`.
- Modifies `doLaunch`'s payload to include `force_clear`.

- [ ] **Step 1: Add state and a checkbox control**

Near the existing `runMode` declaration (`doc-processor-dashboard-view.svelte:242-243`):

```svelte
	type RunMode = 'unfinished' | 'failed' | 'unfinished_failed' | 'force';
	let runMode = $state<RunMode>('failed');
	let forceClear = $state(false);
```

Add a checkbox next to the existing radio group (after the `{/each}` closing the radio markup, ~line 1355), independent of `runMode` per DR1:

```svelte
				<label
					class="flex items-center gap-1.5"
					style="cursor:pointer; font-size:12px; color:{textSecondary}; user-select:none;"
					title="When re-running extract_metrics, clear and re-extract from scratch instead of merging with existing metrics. Ignored by other processors until their own merge-rule ADR lands."
				>
					<input
						type="checkbox"
						checked={forceClear}
						onchange={(e) => { forceClear = (e.target as HTMLInputElement).checked; }}
						style="accent-color:{accent};"
					/>
					Force Clear (metrics only, wipes instead of merging)
				</label>
```

- [ ] **Step 2: Include it in the `doLaunch` payload**

Modify `doLaunch` (lines 444-469):

```svelte
	async function doLaunch(
		record: KbInputRecord,
		procs: Record<string, boolean>,
		reParse: boolean,
		reConvert: boolean
	) {
		if (reParse) {
			await publishEvent('kb.pdf.staged', { record_id: String(record.id), type: record.type ?? 'pdf', status: 'success', force: true });
			return;
		}
		if (reConvert) {
			await publishEvent('kb.pdf.parsed', { record_id: String(record.id), type: 'pdf', status: 'success', force: true });
			return;
		}
		const chosen = buildManualLaunchOperations(selectableProcessorIds, procs, entityExtractionSucceeded(record));
		const payload: Record<string, unknown> = { record_id: String(record.id), force: runMode === 'force', force_clear: forceClear };
		payload.operation = chosen;
		await publishEvent('kb.line-file-generated', payload);
	}
```

- [ ] **Step 3: Manual verification (no frontend test harness in this file per its existing test coverage — confirm none exists first)**

Run: `grep -rn "doc-processor-dashboard-view" web/src/lib/components/home3/*.test.* 2>/dev/null` — if no test file exists for this component, manual verification is the existing convention; start the dev server and confirm the checkbox renders and toggles.

Run: `cd web && bun run dev` (or the project's documented dev command — check `package.json` scripts first)
Expected: dashboard loads, "Force Clear" checkbox appears next to the run-mode radios, toggling it doesn't affect `runMode`.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(frontend): add independent force_clear control to doc-processor dashboard"
```

---

### Task 15: Sync the ADR document with implementation-time findings

**Files:**
- Modify: `KnowledgeStore/doc-repo/adrs/202607/2026071002-adr-doc-processor-incremental.md`

- [ ] **Step 1: Update "Database Migrations"**

Replace the "None required" section with a note that Task 3's unique-constraint migration was added during implementation, and why (live-bug duplicate cleanup + `ON CONFLICT` target requirement for `UpsertMetrics`).

- [ ] **Step 2: Add an implementation note about where the logic actually lives**

Add a short note (e.g. under DR1 or as a new "Implementation Note") recording the Critical Finding: the force/force_clear/merge logic was implemented in `InitChunkBatch`/`ProcessChunk`/`FinalizeChunkBatch`, not `HandleEvent`, because `HandleEvent` is dead code on the live `chunk_batch_coordinator.go` path for any processor implementing `ChunkBatchProcessor` (which all four processors this ADR covers do).

- [ ] **Step 2b: Document the Rule-4 field-reconstruction fix under DR2's "Merge Resolution LLM Call" section**

Add a note that the Merge Resolution LLM's `winning_metrics` response only carries the ~10 fields listed in its schema, and that `mergeAndCollectDirtyMetrics` (Task 12) reconstructs the full row by overlaying only those decided fields onto the winning candidate's full source row (from the pending group) before writing — otherwise fields the LLM doesn't return (`desc`, `context`, `keywords`, `location_type`, `formula_or_definition`, `measurement_frequency`, `category_paths`, `*_en` variants) would be silently blanked on every Rule-4 merge. Note this was found during Task 11's review and fixed in Task 12.

- [ ] **Step 3: Add a Change Log entry**

```markdown
* 2026/07/11, Implementation: added migration for kb.metrics unique constraint
  (dedupe + (input_record_id, metric_id) index) after discovering HandleEvent's
  force/skip logic is dead code on the live chunk-batch-coordinator path;
  DR1-DR4 implemented in InitChunkBatch/ProcessChunk/FinalizeChunkBatch instead;
  fixed a Rule-4 merged-winner field-blanking bug (reconstruct full row from
  source + overlay only LLM-decided fields, rather than writing the LLM's
  sparse output directly); also restored the same force-gated wipe guard for
  extract_provisions, extract_inventory_items, and extract_entity_relation on
  that same live path.
```

- [ ] **Step 4: Commit**

```bash
cd /Users/cding/Workspace/KnowledgeStore && jj commit -m "docs(adr): sync 2026071002 with implementation findings (dead HandleEvent path, new migration)"
```

*(Note: `KnowledgeStore` is its own repo per `Workspace/CLAUDE.md` — this commit is separate from the `ChenWeb` commits above.)*

---

## Self-Review Notes

- **Spec coverage:** DR1 (Task 1, 2, 10) — done. DR2 Metric Groups/Rule-1..4 (Task 5, 7) — done. DR2 Merge Resolution LLM call (Task 8, 9) — done. DR2 transaction/dirty persistence (Task 11, via `UpsertMetrics`'s `ON CONFLICT`) — done. DR3 (Task 6) — done. DR4 enrichment scope (already true by construction — `FinalizeChunkBatch` only ever enriches `p.batchMentions`, this run's candidates; documented in Task 11's comment, no separate code needed) and dirty-check (Task 11's `metricContentEqual` + `ON CONFLICT ... DO UPDATE`) — done. Scope note (other 3 processors accept-and-ignore, restore wipe parity) — Task 12. Frontend — Task 13. ADR sync — Task 14.
- **Placeholder scan:** all steps contain complete, real code; no "TODO"/"handle appropriately" language.
- **Type consistency:** `mergeMetricsResult`, `metricSeqnoCounter`, `docProcessorFlags` are defined once (Tasks 5/6/2) and used with identical names/shapes in every later task that consumes them (Tasks 7, 9, 10, 11).

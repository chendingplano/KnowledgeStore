# Concurrent Doc Processors Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan (this harness runs in a single session). Steps use checkbox (`- [ ]`) syntax for tracking. Run every Go test step with `-race`.

**Goal:** Run the configurable doc processors concurrently within a single record's pipeline, behind `RUN_DOC_PROCESSOR_CONCURRENT` (default `true`), with a concurrency-safe `kb.inputs.status` write so no status entries are lost.

**Architecture:** Split the controller pipeline into Phase A (mandatory processors, sequential) and Phase B (configurable processors, concurrent under a `WaitGroup`). Serialize every `kb.inputs.status` read-modify-write through a per-record sharded mutex via a single `updateInputStatusAtomic` helper. Collect Phase B results without mutating shared controller state.

**Tech Stack:** Go (`ChenWeb/server/api/doc-processing`, `ChenWeb/server/cmd/doc-processor`), PostgreSQL JSONB status column, NATS JetStream. Spec: `docs/superpowers/specs/2026-06-01-concurrent-doc-processors-design.md`.

**Reference files (read before starting):**
- `ChenWeb/server/api/doc-processing/control.go` — `handleEvent`, `runSingleProcessor`, `persistPipelineStatus`
- `ChenWeb/server/api/doc-processing/control_test.go` — fakes (`fakeProcessor`, `blockBufferSettingProcessor`)
- `ChenWeb/server/api/doc-processing/extract-doc-metadata-store.go` — `DocMetadataStore`, `UpdateInputMetadata`, `DocMetadataUpdate`
- `ChenWeb/server/cmd/doc-processor/main.go:74-105` — `filterConfiguredProcessors` (authoritative mandatory set)

**Authoritative mandatory (Phase A) set**, from `main.go:78-82`, canonical names: `static_analyzer`, `chunking`, `extract_doc_metadata`. Everything else in `ControlService.Processors` is Phase B. `blocking` runs before both phases as today (`BlockingProcessor`, not in the `Processors` slice).

---

## Chunk 1: Per-record status lock + atomic helper

Closes the lost-update race. No behavior change yet (still sequential), so this chunk is independently shippable and safe.

### Task 1: Sharded per-record status lock

**Files:**
- Create: `ChenWeb/server/api/doc-processing/status_lock.go`
- Test: `ChenWeb/server/api/doc-processing/status_lock_test.go`

- [ ] **Step 1: Write the failing test**

```go
package docprocessing

import (
	"sync"
	"testing"
)

func TestLockRecordStatus_SerializesSameRecord(t *testing.T) {
	const goroutines = 50
	var counter int
	var wg sync.WaitGroup
	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			unlock := lockRecordStatus(42)
			defer unlock()
			counter++ // racy without the lock; -race must stay clean
		}()
	}
	wg.Wait()
	if counter != goroutines {
		t.Fatalf("counter=%d, want %d", counter, goroutines)
	}
}

func TestLockRecordStatus_DifferentRecordsDoNotDeadlock(t *testing.T) {
	unlockA := lockRecordStatus(1)
	unlockB := lockRecordStatus(2) // different shard target; must not block
	unlockB()
	unlockA()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ChenWeb/server && go test -race ./api/doc-processing/ -run TestLockRecordStatus -v`
Expected: FAIL — `lockRecordStatus` undefined.

- [ ] **Step 3: Write minimal implementation**

```go
package docprocessing

import "sync"

// recordStatusLockShards is the number of mutexes striping kb.inputs.status
// writes by record_id. A fixed array keeps memory bounded and leak-free.
const recordStatusLockShards = 256

var recordStatusLocks [recordStatusLockShards]sync.Mutex

// lockRecordStatus acquires the mutex guarding kb.inputs.status writes for the
// given record_id and returns its unlock function. It serializes the
// read-modify-write of the status JSON so concurrent processors do not clobber
// each other's entries.
//
// CONSTRAINT (single instance only): this lock coordinates goroutines within
// one process. If doc-processor is ever scaled to multiple replicas, replace
// this with a DB row lock (SELECT ... FOR UPDATE + jsonb_set) or a shared
// coordinator (Redis / dedicated primary). See
// docs/superpowers/specs/2026-06-01-concurrent-doc-processors-design.md.
func lockRecordStatus(id int64) func() {
	shard := uint64(id) % recordStatusLockShards
	m := &recordStatusLocks[shard]
	m.Lock()
	return m.Unlock
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ChenWeb/server && go test -race ./api/doc-processing/ -run TestLockRecordStatus -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ChenWeb && git add server/api/doc-processing/status_lock.go server/api/doc-processing/status_lock_test.go
git commit -m "feat(doc-processor): add per-record status lock"
```

### Task 2: `updateInputStatusAtomic` helper

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/status_lock.go`
- Test: `ChenWeb/server/api/doc-processing/status_lock_test.go`

- [ ] **Step 1: Write the failing test** (a fake store that simulates a read-modify-write; without the lock the concurrent appends lose entries)

```go
type fakeStatusStore struct {
	mu  sync.Mutex // guards the simulated DB cell only (not the RMW window)
	raw string
}

func (s *fakeStatusStore) GetInputRecord(_ context.Context, _ int64) (DocMetadataInputRecord, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return DocMetadataInputRecord{StatusRaw: s.raw}, nil
}

func (s *fakeStatusStore) UpdateInputMetadata(_ context.Context, _ int64, upd DocMetadataUpdate) error {
	time.Sleep(time.Millisecond) // widen the RMW window so a missing lock loses updates
	s.mu.Lock()
	defer s.mu.Unlock()
	s.raw = upd.StatusRaw
	return nil
}

func TestUpdateInputStatusAtomic_NoLostUpdates(t *testing.T) {
	store := &fakeStatusStore{raw: "[]"}
	const n = 20
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		i := i
		wg.Add(1)
		go func() {
			defer wg.Done()
			_ = updateInputStatusAtomic(context.Background(), store, 7, func(cur string) (DocMetadataUpdate, error) {
				var arr []map[string]any
				_ = json.Unmarshal([]byte(cur), &arr)
				arr = append(arr, map[string]any{"operation": fmt.Sprintf("op-%d", i)})
				b, _ := json.Marshal(arr)
				return DocMetadataUpdate{StatusRaw: string(b)}, nil
			})
		}()
	}
	wg.Wait()
	var arr []map[string]any
	if err := json.Unmarshal([]byte(store.raw), &arr); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(arr) != n {
		t.Fatalf("got %d entries, want %d (lost updates)", len(arr), n)
	}
}
```

Add imports as needed (`context`, `encoding/json`, `fmt`, `time`). Note `fakeStatusStore` implements the subset of `DocMetadataStore` the helper uses; if the interface has more methods, embed it or add no-op stubs.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ChenWeb/server && go test -race ./api/doc-processing/ -run TestUpdateInputStatusAtomic -v`
Expected: FAIL — `updateInputStatusAtomic` undefined (and, once defined without the lock, fewer than `n` entries / `-race` data race).

- [ ] **Step 3: Write minimal implementation**

```go
// statusStore is the minimal surface updateInputStatusAtomic needs. It is
// satisfied by DocMetadataStore.
type statusStore interface {
	GetInputRecord(ctx context.Context, id int64) (DocMetadataInputRecord, error)
	UpdateInputMetadata(ctx context.Context, id int64, upd DocMetadataUpdate) error
}

// updateInputStatusAtomic performs the kb.inputs.status read-modify-write under
// the per-record lock. mutate receives the current status JSON and returns the
// DocMetadataUpdate to persist (its StatusRaw must be the new status array;
// other fields may also be set and are written under the same lock).
func updateInputStatusAtomic(
	ctx context.Context,
	store statusStore,
	id int64,
	mutate func(currentStatusRaw string) (DocMetadataUpdate, error),
) error {
	unlock := lockRecordStatus(id)
	defer unlock()
	rec, err := store.GetInputRecord(ctx, id)
	if err != nil {
		return err
	}
	upd, err := mutate(rec.StatusRaw)
	if err != nil {
		return err
	}
	return store.UpdateInputMetadata(ctx, id, upd)
}
```

If `DocMetadataStore.GetInputRecord` returns a type other than `DocMetadataInputRecord`, align the `statusStore` signature to match it exactly.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ChenWeb/server && go test -race ./api/doc-processing/ -run TestUpdateInputStatusAtomic -v`
Expected: PASS, no data race.

- [ ] **Step 5: Commit**

```bash
cd ChenWeb && git add server/api/doc-processing/status_lock.go server/api/doc-processing/status_lock_test.go
git commit -m "feat(doc-processor): add atomic kb.inputs.status update helper"
```

### Task 3: Route controller `persistPipelineStatus` through the helper

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/control.go:315-344` (`persistPipelineStatus`)

- [ ] **Step 1: Write the failing test** — concurrent `persistPipelineStatus` calls keep all entries.

`control_test.go`:
```go
func TestPersistPipelineStatus_ConcurrentNoLostUpdates(t *testing.T) {
	store := &fakeStatusStore{raw: "[]"}
	svc := &ControlService{InputStore: store, Now: time.Now}
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		i := i
		wg.Add(1)
		go func() {
			defer wg.Done()
			svc.persistPipelineStatus(context.Background(), 7, "running", fmt.Sprintf("proc-%d", i), nil)
		}()
	}
	wg.Wait()
	// All concurrent writers collapse onto the single doc_processing entry, but
	// the test's real assertion is the -race flag staying clean and no panic.
	if store.raw == "" {
		t.Fatal("status not written")
	}
}
```

Note: `persistPipelineStatus` replaces the single `doc_processing` entry (see `appendPipelineStatus`), so the count won't grow — the meaningful guarantee here is **no data race / no torn write**. The cross-operation lost-update guarantee is covered by Task 2 and the integration test in Chunk 4. If `fakeStatusStore` does not satisfy the full `DocMetadataStore` interface required by `InputStore`, extend it with the missing method stubs.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ChenWeb/server && go test -race ./api/doc-processing/ -run TestPersistPipelineStatus_Concurrent -v`
Expected: FAIL with a data race (pre-refactor `persistPipelineStatus` does an unlocked read-modify-write).

- [ ] **Step 3: Refactor `persistPipelineStatus`** to use `updateInputStatusAtomic`:

```go
func (s *ControlService) persistPipelineStatus(ctx context.Context, recordID int64, procStatus string, processorName string, procErr error) {
	if s.InputStore == nil || recordID <= 0 {
		return
	}
	err := updateInputStatusAtomic(ctx, s.InputStore, recordID, func(current string) (DocMetadataUpdate, error) {
		statusRaw, err := appendPipelineStatus(current, s.now(), procStatus, processorName, procErr)
		if err != nil {
			return DocMetadataUpdate{}, err
		}
		var errMsg *string
		if procErr != nil {
			msg := strings.TrimSpace(procErr.Error())
			errMsg = &msg
		}
		return DocMetadataUpdate{StatusRaw: statusRaw, ErrorMsg: errMsg}, nil
	})
	if err != nil && s.Logger != nil {
		s.Logger.Error("failed persisting doc pipeline status", "record_id", recordID, "error", err)
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ChenWeb/server && go test -race ./api/doc-processing/ -run TestPersistPipelineStatus_Concurrent -v`
Expected: PASS, no race.

- [ ] **Step 5: Run the full package to confirm no regression**

Run: `cd ChenWeb/server && go test -race ./api/doc-processing/...`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd ChenWeb && git add server/api/doc-processing/control.go server/api/doc-processing/control_test.go
git commit -m "refactor(doc-processor): make pipeline status write atomic"
```

---

## Chunk 2: Retrofit every processor status write

Every concurrent (Phase B) processor's own status write must also go through `updateInputStatusAtomic`, or it will race the controller and its peers. Phase A processors are retrofitted too for uniformity (low risk, future-proof).

### Task 4: Enumerate all status-write sites

- [ ] **Step 1: List the sites**

Run:
```bash
cd ChenWeb/server/api/doc-processing && grep -rn "UpdateInputMetadata" --include="*.go" . | grep -v "_test.go"
```
Expected sites (verify against output; line numbers drift): `extract-provisions.go`, `extract-doc-metadata.go`, `fix-size-chunking.go` (chunking + generate_summaries + generate_topics), `generate-scene-blocks-processor.go`, `extract-inventory-items.go`, `extract-metrics.go`, `extract-semantic-projections.go`, `extract-structured-knowledge.go`, `extract-entity-relation.go`. Record the full list in a scratch note.

- [ ] **Step 2: Classify each** as status-only (StatusRaw is the only field set) or status+metadata (e.g. `extract-doc-metadata.go` also writes Title/DocNo). Both use the same helper; status+metadata sites set the extra fields inside the returned `DocMetadataUpdate`.

### Task 5: Retrofit pattern (apply per processor, one commit each)

For **each** site, apply this mechanical transform. Reference site: `extract-provisions.go:1300-1313`.

**Before:**
```go
rec, err := p.InputStore.GetInputRecord(ctx, recordID) // or an already-loaded rec
statusRaw, err := appendProvisionsStatus(rec.StatusRaw, params)
if err != nil { /* handle */ }
if err := p.InputStore.UpdateInputMetadata(ctx, rec.ID, DocMetadataUpdate{StatusRaw: statusRaw}); err != nil { /* handle */ }
```

**After:**
```go
if err := updateInputStatusAtomic(ctx, p.InputStore, recordID, func(current string) (DocMetadataUpdate, error) {
	statusRaw, err := appendProvisionsStatus(current, params)
	if err != nil {
		return DocMetadataUpdate{}, err
	}
	return DocMetadataUpdate{StatusRaw: statusRaw}, nil
}); err != nil { /* same error handling as before */ }
```

Rules:
- The `append*Status` call must take the helper's `current` argument, **not** a previously-read `rec.StatusRaw`. This is the whole point — re-read inside the lock.
- If the site reads other `rec` fields (e.g. input filename) for non-status purposes, keep that read **outside** the helper; only the status RMW moves inside.
- For status+metadata sites, set the additional `DocMetadataUpdate` fields inside the returned struct so they are written under the same lock.
- Preserve the exact existing error handling and logging.

Per processor (each is its own task — write/adjust a focused test if one exists, transform the site(s), run `go test -race` for that processor's `_test.go`, commit):

- [ ] **Task 5a:** `extract-provisions.go` (all status sites) → `go test -race ./api/doc-processing/ -run Provisions` → commit `refactor(doc-processor): atomic status writes in provisions`
- [ ] **Task 5b:** `fix-size-chunking.go` — chunking, `generate_summaries`, `generate_topics` status sites → `go test -race ./api/doc-processing/ -run 'Chunk|Topic|Summar'` → commit
- [ ] **Task 5c:** `generate-scene-blocks-processor.go` → `go test -race ./api/doc-processing/ -run Scene` → commit
- [ ] **Task 5d:** `extract-inventory-items.go` → `go test -race ./api/doc-processing/ -run Inventory` → commit
- [ ] **Task 5e:** `extract-metrics.go` → `go test -race ./api/doc-processing/ -run Metrics` → commit
- [ ] **Task 5f:** `extract-semantic-projections.go` → `go test -race ./api/doc-processing/ -run Semantic` → commit
- [ ] **Task 5g:** `extract-structured-knowledge.go` → `go test -race ./api/doc-processing/ -run Knowledge` → commit
- [ ] **Task 5h:** `extract-entity-relation.go` → `go test -race ./api/doc-processing/ -run Entity` → commit
- [ ] **Task 5i:** `extract-doc-metadata.go` (status+metadata sites) → `go test -race ./api/doc-processing/ -run Metadata` → commit

- [ ] **Final step:** `cd ChenWeb/server && go test -race ./api/doc-processing/...` → PASS.

---

## Chunk 3: Two-phase concurrent controller

### Task 6: Phase classification helper

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/control.go`
- Test: `ChenWeb/server/api/doc-processing/control_test.go`

- [ ] **Step 1: Failing test**

```go
func TestIsPhaseAProcessor(t *testing.T) {
	for _, name := range []string{"static_analyzer", "chunking", "extract_doc_metadata", "extract_metadata"} {
		if !isPhaseAProcessor(name) {
			t.Errorf("%q should be Phase A", name)
		}
	}
	for _, name := range []string{"extract_metrics", "generate_topics", "extract_entity_relation"} {
		if isPhaseAProcessor(name) {
			t.Errorf("%q should be Phase B", name)
		}
	}
}
```

- [ ] **Step 2: Run → FAIL** (`isPhaseAProcessor` undefined).

- [ ] **Step 3: Implement** (mirror `main.go:78-82`, normalize via `canonicalOperationName`):

```go
// isPhaseAProcessor reports whether the named processor is a mandatory,
// sequential Phase A processor. Must stay in sync with the mandatory set in
// cmd/doc-processor/main.go filterConfiguredProcessors.
func isPhaseAProcessor(name string) bool {
	switch canonicalOperationName(name) {
	case "static_analyzer", "chunking", "extract_doc_metadata":
		return true
	default:
		return false
	}
}
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(doc-processor): add Phase A/B classification`.

### Task 7: Extract result-collecting processor runner

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/control.go:275-313` (`runSingleProcessor`)

- [ ] **Step 1:** Introduce `procResult` and `runSingleProcessorCollect`, then make `runSingleProcessor` a thin wrapper so existing sequential behavior is byte-for-byte unchanged.

```go
type procResult struct {
	failed  bool
	stopped bool
	err     error
}

// runSingleProcessorCollect runs one processor and returns its outcome without
// mutating shared controller state, so it is safe to call from concurrent
// goroutines. All status writes inside go through updateInputStatusAtomic.
func (s *ControlService) runSingleProcessorCollect(ctx context.Context, payload []byte, p Processor, recordID int64) procResult {
	procStart := s.now()
	processorName := processorLogName(p)
	if s.Logger != nil {
		s.Logger.Info("start running processor", "record_id", recordID, "processor", processorName)
	}
	s.persistPipelineStatus(ctx, recordID, "running", processorName, nil)
	if err := p.HandleEvent(ctx, payload); err != nil {
		res := procResult{failed: true, err: err}
		procStatus := "failed"
		if errors.Is(err, ErrPipelineStopped) || isCtxStopped(ctx) {
			res.stopped = true
			procStatus = "stopped"
			if s.Logger != nil {
				s.Logger.Info("processor stopped by user request", "processor", processorName, "record_id", recordID)
			}
		} else if s.Logger != nil {
			s.Logger.Error("doc processor failed", "processor", processorName, "error", err)
		}
		if s.Logger != nil {
			s.Logger.Info("finish running processor", "record_id", recordID, "processor", processorName, "proc_status", procStatus, "ms_used", time.Since(procStart).Milliseconds())
		}
		return res
	}
	if s.Logger != nil {
		s.Logger.Info("finish running processor", "record_id", recordID, "processor", processorName, "proc_status", "success", "ms_used", time.Since(procStart).Milliseconds())
	}
	return procResult{}
}

func (s *ControlService) runSingleProcessor(ctx context.Context, payload []byte, p Processor, recordID int64, requestFailed *bool, firstErr *error) {
	res := s.runSingleProcessorCollect(ctx, payload, p, recordID)
	if res.failed {
		*requestFailed = true
		if *firstErr == nil {
			*firstErr = res.err
		}
	}
}
```

- [ ] **Step 2:** Run the existing controller tests to prove no behavior change.

Run: `cd ChenWeb/server && go test -race ./api/doc-processing/ -run TestControlService`
Expected: PASS (existing ordering/stop/buffer tests unchanged).

- [ ] **Step 3: Commit** `refactor(doc-processor): collect processor results without shared state`.

### Task 8: Two-phase execution + flag

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/control.go` (`ControlService`, `handleEvent` loop region `233-260`)
- Test: `ChenWeb/server/api/doc-processing/control_test.go`

- [ ] **Step 1: Failing tests**

Add a concurrency-safe recorder (the existing `fakeProcessor` appends to a shared slice without locking — unsafe under Phase B):
```go
type concurrentRecorder struct {
	mu    sync.Mutex
	calls []string
}
func (r *concurrentRecorder) add(s string) { r.mu.Lock(); r.calls = append(r.calls, s); r.mu.Unlock() }

type recordingProcessor struct {
	name string
	rec  *concurrentRecorder
	hook func() // optional, to assert overlap
}
func (p recordingProcessor) Name() string { return p.name }
func (p recordingProcessor) LogName() string { return p.name }
func (p recordingProcessor) HandleEvent(_ context.Context, _ []byte) error {
	p.rec.add("start:" + p.name)
	if p.hook != nil { p.hook() }
	p.rec.add("end:" + p.name)
	return nil
}
```

Tests:
```go
// Phase A runs strictly before any Phase B processor starts.
func TestTwoPhase_PhaseABeforePhaseB(t *testing.T) {
	rec := &concurrentRecorder{}
	t.Setenv("RUN_DOC_PROCESSOR_CONCURRENT", "true")
	svc := &ControlService{
		Processors: []Processor{
			recordingProcessor{name: "static_analyzer", rec: rec},
			recordingProcessor{name: "chunking", rec: rec},
			recordingProcessor{name: "extract_doc_metadata", rec: rec},
			recordingProcessor{name: "extract_metrics", rec: rec},
			recordingProcessor{name: "generate_topics", rec: rec},
		},
	}
	svc.HandleEvent(context.Background(), []byte(`{"record_id":"1"}`))
	// Every Phase A start/end appears before any Phase B start.
	firstPhaseB := indexOfPrefix(rec.calls, "start:extract_metrics", "start:generate_topics")
	for _, a := range []string{"end:static_analyzer", "end:chunking", "end:extract_doc_metadata"} {
		if idx := indexOf(rec.calls, a); idx == -1 || idx > firstPhaseB {
			t.Fatalf("%s did not complete before Phase B (calls=%v)", a, rec.calls)
		}
	}
}

// Phase B processors overlap (true concurrency).
func TestTwoPhase_PhaseBOverlaps(t *testing.T) {
	t.Setenv("RUN_DOC_PROCESSOR_CONCURRENT", "true")
	rec := &concurrentRecorder{}
	started := make(chan struct{}, 2)
	release := make(chan struct{})
	hook := func() { started <- struct{}{}; <-release }
	svc := &ControlService{
		Processors: []Processor{
			recordingProcessor{name: "extract_metrics", rec: rec, hook: hook},
			recordingProcessor{name: "generate_topics", rec: rec, hook: hook},
		},
	}
	done := make(chan struct{})
	go func() { svc.HandleEvent(context.Background(), []byte(`{"record_id":"1"}`)); close(done) }()
	<-started; <-started // both must start before either is released → proves overlap
	close(release)
	<-done
}

// Flag off → sequential order preserved (reuses existing fakeProcessor).
func TestTwoPhase_FlagOffIsSequential(t *testing.T) {
	t.Setenv("RUN_DOC_PROCESSOR_CONCURRENT", "false")
	got := make([]string, 0, 3)
	svc := &ControlService{Processors: []Processor{
		fakeProcessor{name: "extract_metrics", calls: &got},
		fakeProcessor{name: "generate_topics", calls: &got},
	}}
	svc.HandleEvent(context.Background(), []byte(`{"record_id":"1"}`))
	want := []string{"extract_metrics", "generate_topics"}
	if !equalStrings(got, want) { t.Fatalf("got %v want %v", got, want) }
}

// One Phase B failure does not stop siblings; run is classified failed.
func TestTwoPhase_FailureIsolation(t *testing.T) {
	t.Setenv("RUN_DOC_PROCESSOR_CONCURRENT", "true")
	rec := &concurrentRecorder{}
	svc := &ControlService{Processors: []Processor{
		failingRecordingProcessor{name: "extract_metrics", rec: rec},
		recordingProcessor{name: "generate_topics", rec: rec},
	}}
	err := svc.handleEvent(context.Background(), []byte(`{"record_id":"1"}`))
	if err == nil { t.Fatal("expected failure error") }
	if indexOf(rec.calls, "end:generate_topics") == -1 {
		t.Fatal("sibling did not complete despite peer failure")
	}
}
```

Add small helpers `indexOf`, `indexOfPrefix`, `equalStrings`, and `failingRecordingProcessor` (a `recordingProcessor` returning an error). Keep them in `control_test.go`.

- [ ] **Step 2: Run → FAIL** (flag/two-phase not implemented; `TestTwoPhase_PhaseBOverlaps` will hang/timeout because today's sequential loop never starts both — run with `-timeout 30s`).

Run: `cd ChenWeb/server && go test -race -timeout 30s ./api/doc-processing/ -run TestTwoPhase -v`

- [ ] **Step 3: Implement.** Add the flag reader and split the loop.

Add env helper:
```go
// RunDocProcessorConcurrentFromEnv reports whether Phase B processors run
// concurrently. Defaults to true; set RUN_DOC_PROCESSOR_CONCURRENT=false to
// fall back to the sequential pipeline.
func RunDocProcessorConcurrentFromEnv() bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv("RUN_DOC_PROCESSOR_CONCURRENT")))
	return v != "false"
}
```

In `handleEvent`, replace the existing `for _, p := range processors { ... }` block (lines 233-260) with a dispatch. Keep the **exact** existing loop body as `runProcessorsSequential` (so flag-off behavior is identical, including the block-buffer clear and stop reconciliation):

```go
if RunDocProcessorConcurrentFromEnv() {
	s.runProcessorsTwoPhase(ctx, payload, processors, evt.RecordID, &requestFailed, &requestStopped, &firstErr)
} else {
	s.runProcessorsSequential(ctx, payload, processors, evt.RecordID, &requestFailed, &requestStopped, &firstErr)
}
if requestStopped {
	return nil // matches today's early-return semantics
}
```

`runProcessorsSequential` = the current loop body, moved verbatim, returning early via the `requestStopped` flag instead of `return nil` inline (set `*requestStopped = true` and `return`).

`runProcessorsTwoPhase`:
```go
func (s *ControlService) runProcessorsTwoPhase(ctx context.Context, payload []byte, processors []Processor, recordID int64, requestFailed, requestStopped *bool, firstErr *error) {
	var phaseB []Processor
	// Phase A: sequential, preserves block-buffer clear + stop checks.
	for _, p := range processors {
		if p == nil {
			continue
		}
		if !isPhaseAProcessor(p.Name()) {
			phaseB = append(phaseB, p)
			continue
		}
		if isCtxStopped(ctx) {
			*requestStopped = true
			return
		}
		s.runSingleProcessor(ctx, payload, p, recordID, requestFailed, firstErr)
		if !*requestFailed && canonicalOperationName(p.Name()) == "static_analyzer" {
			clearBlockBufferInContext(ctx)
		}
		if *requestFailed && isCtxStopped(ctx) {
			*requestFailed = false
			*firstErr = nil
			*requestStopped = true
			return
		}
	}
	if isCtxStopped(ctx) {
		*requestStopped = true
		return
	}
	if len(phaseB) == 0 {
		return
	}
	// Phase B: concurrent, independent goroutines (no cancel-on-first-error).
	results := make([]procResult, len(phaseB))
	var wg sync.WaitGroup
	for i, p := range phaseB {
		wg.Add(1)
		go func(i int, p Processor) {
			defer wg.Done()
			defer func() {
				if r := recover(); r != nil {
					results[i] = procResult{failed: true, err: fmt.Errorf("(MID_26060101) processor %q panicked: %v", p.Name(), r)}
					if s.Logger != nil {
						s.Logger.Error("doc processor panicked", "processor", p.Name(), "record_id", recordID, "panic", r)
					}
				}
			}()
			results[i] = s.runSingleProcessorCollect(ctx, payload, p, recordID)
		}(i, p)
	}
	wg.Wait()
	for _, r := range results {
		if r.failed {
			*requestFailed = true
			if *firstErr == nil {
				*firstErr = r.err
			}
		}
	}
	// A stop during Phase B reclassifies the whole run as stopped.
	if isCtxStopped(ctx) {
		*requestFailed = false
		*firstErr = nil
		*requestStopped = true
	}
}
```

Confirm `os` and `fmt` are imported (they are). Ensure the `handleEvent` deferred status writer still classifies `requestStopped`/`requestFailed` correctly (unchanged).

- [ ] **Step 4: Run → PASS** (all `TestTwoPhase*` and existing `TestControlService*`).

Run: `cd ChenWeb/server && go test -race -timeout 60s ./api/doc-processing/ -run 'TestTwoPhase|TestControlService' -v`

- [ ] **Step 5: Commit** `feat(doc-processor): run configurable processors concurrently behind flag`.

---

## Chunk 4: Safety audit, integration test, wiring, docs

### Task 9: Chunk-buffer read-only verification + race test

**Files:**
- Test: `ChenWeb/server/api/doc-processing/control_test.go`
- Possibly modify any chunk-consumer that mutates `buf.Chunks`.

- [ ] **Step 1:** Audit every `ChunkBufferFromContext` caller (grep) and confirm none mutate the returned `buf.Chunks` (no append/index-assign to the shared slice; copy before mutating if needed).
- [ ] **Step 2:** Add a `-race` test driving multiple goroutines that each call `ChunkBufferFromContext` and read `Chunks` while another populates it once via `storeChunksInContext`, asserting no race and stable reads.
- [ ] **Step 3:** Run `go test -race`, fix any mutation found, commit `test(doc-processor): cover concurrent chunk-buffer reads`.

### Task 10: Thread-safety audit of `extract_products` and `extract_structured_knowledge`

- [ ] **Step 1:** Inspect `extract-products.go` and `extract-structured-knowledge.go` for package-level mutable state, shared maps/slices written during `HandleEvent`, or shared non-reentrant clients. (`extract_products` is currently commented out in `main.go:203` — note it must be audited before it is ever enabled in Phase B.)
- [ ] **Step 2:** If shared mutable state exists, make it goroutine-local or guard it; otherwise document "audited: no shared mutable state" in the file header comment.
- [ ] **Step 3:** Commit `chore(doc-processor): audit products/structured-knowledge for concurrency`.

### Task 11: End-to-end no-lost-status integration test

**Files:**
- Test: `ChenWeb/server/api/doc-processing/control_test.go`

- [ ] **Step 1:** With `RUN_DOC_PROCESSOR_CONCURRENT=true`, a `fakeStatusStore`-backed `ControlService`, and several Phase B `recordingProcessor`s that each write a distinct status entry via `updateInputStatusAtomic` inside `HandleEvent`, run the pipeline and assert **every** processor's status entry survives in the final status JSON (this is the real lost-update regression guard). Run with `-race`.
- [ ] **Step 2:** Run → PASS. Commit `test(doc-processor): assert no status entries lost under concurrency`.

### Task 12: Flag wiring + config + docs

**Files:**
- Modify: `ChenWeb/server/cmd/doc-processor/main.go` (log the resolved flag at startup for observability)
- Modify: `ChenWeb/server/config.toml` (document the env var; no value needed since it's env-driven, default true)
- Modify: `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`

- [ ] **Step 1:** In `main.go`, after config load, log `RUN_DOC_PROCESSOR_CONCURRENT` resolved value (`docprocessing.RunDocProcessorConcurrentFromEnv()`) so operators can confirm the mode.
- [ ] **Step 2:** Update the capsule:
  - Add a "Concurrency" subsection: Phase A (mandatory, sequential) vs Phase B (configurable, concurrent); the `RUN_DOC_PROCESSOR_CONCURRENT` flag (default true) as kill-switch.
  - Amend the "JetStream Request" ordering note: the "applied in the order listed" guarantee holds for mandatory/Phase A only; Phase B order is unspecified.
  - Document the single-instance status-lock constraint and the future scale-out path (DB row lock / Redis).
- [ ] **Step 3:** Commit `docs(doc-processor): document concurrent pipeline and flag`.

### Task 13: Full verification

- [ ] **Step 1:** `cd ChenWeb/server && go build ./...` → success.
- [ ] **Step 2:** `cd ChenWeb/server && go test -race ./api/doc-processing/...` → PASS.
- [ ] **Step 3:** `cd /Users/cding/Workspace && go vet ./...` (workspace-aware) on affected modules → clean.
- [ ] **Step 4:** Manual staging check: process a representative document with the flag on; confirm wall-clock drops from ~Σ(processor) toward ~max(processor), and that `kb.inputs.status` contains a terminal entry for every expected processor (Record Completion Criteria satisfied). Then toggle `RUN_DOC_PROCESSOR_CONCURRENT=false` and confirm the sequential path still works.

---

## Idempotency verification (carry through implementation)

While retrofitting each Phase B processor (Chunk 2), confirm its output write replaces by `record_id` (upsert / delete-then-insert), not append, so the `force`-reprocess and retry paths don't duplicate artifacts. `extract-provisions.go` already upserts (`status = EXCLUDED.status`). Note any processor that appends and fix it (or file a follow-up if out of scope) — flag to the user rather than silently changing output semantics.

## Out of scope (do not implement here)

- DB-side `jsonb_set` atomic status writes / row locks (the multi-instance solution).
- In-memory status store, new status API, crash reconciliation.
- Global LLM concurrency limiter (provider budget has headroom: 7×30 ≈ 210 ≪ 2500).
- Overlapping `extract_metadata` into Phase B, or re-blocking once and sharing the buffer.
- Enabling `extract_products` (stays commented in `main.go` until audited).

## Implementations
Refer to [1] for the implementations.

## References
[1] KnowledgeStore/Capsules/coding-capsules/concurrent-doc-processors/concurrent-doc-processors-impl.md
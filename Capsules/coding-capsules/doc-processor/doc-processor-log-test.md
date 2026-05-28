# Doc Processor Log — Test Plan

## Unit Tests (Go)

### `doc_proc_log_store_test.go`

Location: `ChenWeb/server/api/doc-processing/`

#### `TestInsertDocProcLog_LLMCall`
- Insert a record with `entry_type = 'llm_call'`.
- Assert no error returned.
- Query the row back; verify `doc_proc_name`, `entry_type`, `pass`, `llm_call_id`, `activity_name`, `start_time`, `end_time` match.

#### `TestInsertDocProcLog_Summary`
- Insert a record with `entry_type = 'doc_proc_summary'`.
- Verify `pass`, `llm_call_id`, `activity_name` are NULL.

#### `TestInsertDocProcLog_MissingDocProcName`
- Pass empty `DocProcName`.
- Expect a non-nil error.

#### `TestInsertDocProcLog_InvalidEntryType`
- Pass `EntryType = 'unknown'`.
- Expect a non-nil error (or DB constraint violation).

#### `TestListDocProcLogs_NoFilter`
- Insert 5 rows (mix of entry types and processor names).
- Call `ListDocProcLogs` with empty filter.
- Expect total = 5, results sorted by `create_time DESC`.

#### `TestListDocProcLogs_FilterByEntryType`
- Insert 3 `llm_call` and 2 `doc_proc_summary` rows.
- Filter `entry_type = 'llm_call'`.
- Expect total = 3.

#### `TestListDocProcLogs_FilterByDocProcName`
- Insert rows for `extract_metrics` (3) and `chunking` (2).
- Filter `doc_proc_name = 'extract_metrics'`.
- Expect total = 3.

#### `TestListDocProcLogs_Pagination`
- Insert 10 rows.
- Page 1, page_size 3: expect 3 results, total 10.
- Page 4, page_size 3: expect 1 result.

#### `TestDeleteOldDocProcLogs`
- Insert 2 rows with `create_time = NOW() - interval '40 days'` (backdated via raw SQL).
- Insert 2 rows with `create_time = NOW()`.
- Call `DeleteOldDocProcLogs(ctx, 30)`.
- Expect 2 rows deleted; 2 rows remain.

#### `TestDeleteOldDocProcLogs_InvalidDays`
- Call with `retentionDays = 0`.
- Expect error.

#### `TestPGTextArrayScan_Empty`
- Scan `"{}"` → expect `[]string{}`.

#### `TestPGTextArrayScan_Values`
- Scan `"{claude-sonnet-4-6,gpt-4o}"` → expect `["claude-sonnet-4-6", "gpt-4o"]`.

#### `TestDocProcLogger_LogLLMCall`
- Construct `DocProcLogger{DB: testDB}`.
- Call `LogLLMCall` with a valid record.
- Verify row exists in `kb.doc_proc_logs` with `entry_type = 'llm_call'`.

#### `TestDocProcLogger_LogSummary`
- Call `LogSummary` with a valid record.
- Verify `entry_type = 'doc_proc_summary'`.

---

## HTTP Handler Tests

### `doc_proc_log_handler_test.go`

Location: `ChenWeb/server/api/kbhandler/`

#### `TestListDocProcLogs_200`
- Mock `ApiTypes.ProjectDBHandle` with pre-inserted rows.
- `GET /api/v1/kb/doc-proc-logs` → 200, `status: true`, `results` array present.

#### `TestListDocProcLogs_FilterParams`
- `GET /api/v1/kb/doc-proc-logs?entry_type=llm_call&doc_proc_name=extract_metrics` → confirm filters forwarded to store.

#### `TestListDocProcLogs_InvalidPageSize`
- `page_size=10000` → capped to 500 by handler; no error.

#### `TestDeleteOldDocProcLogs_200`
- `DELETE /api/v1/kb/doc-proc-logs/old?days=30` → 200, `status: true`, `deleted` count in body.

#### `TestDeleteOldDocProcLogs_MissingDays`
- `DELETE /api/v1/kb/doc-proc-logs/old` (no `days` param) → 400, `status: false`.

#### `TestDeleteOldDocProcLogs_InvalidDays`
- `DELETE /api/v1/kb/doc-proc-logs/old?days=0` → 400.

---

## Frontend Manual Tests

### Doc Processor Logs View

1. **Navigation** — Open `ChenWeb` home3, expand SYSTEM ADMIN in the nav rail, click "Doc Processor Logs". The view loads without errors.

2. **Empty state** — When the table is empty, the message "No log entries found." is displayed.

3. **Log table loads** — After inserting test rows via the Go logger, refresh the view. Rows appear with correct Type badge (LLM Call / Summary), Processor name, Duration.

4. **Filter by entry type** — Select "LLM Call" in the Type filter and click Search. Only `llm_call` entries show. Clear filter and verify all entries return.

5. **Filter by processor name** — Type `extract_metrics` and click Search. Only rows for that processor show.

6. **Row expand** — Click a row with `extra_info` or `artifact`. The expansion panel opens with pretty-printed JSON.

7. **Row collapse** — Click the same row again. The expansion panel closes.

8. **Error row** — Verify rows with a non-empty `errors` field show in red; rows with no error show "OK" in green.

9. **Pagination** — Insert more than 50 rows. Verify "Next" button is enabled; clicking it loads page 2.

10. **Retention apply** — Set days = 1. Click "Apply Retention". A success message appears and the table refreshes.

11. **Retention error** — Set days = 0 (or clear the field). Click "Apply Retention". An error message appears; the table is not modified.

12. **Dark mode** — Toggle dark mode. All text, backgrounds, and borders update correctly.

---

## Integration Checklist

- [ ] Migration `20260527000020` runs cleanly on a fresh database (`goose up`).
- [ ] Migration rolls back cleanly (`goose down`).
- [ ] Go workspace builds without errors: `cd ChenWeb && go build ./...`
- [ ] Frontend builds without errors: `cd ChenWeb/web && bun run build`
- [ ] `GET /api/v1/kb/doc-proc-logs` returns `401` when not authenticated.
- [ ] `DELETE /api/v1/kb/doc-proc-logs/old?days=30` returns `401` when not authenticated.

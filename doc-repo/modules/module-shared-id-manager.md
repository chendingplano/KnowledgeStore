# Module: Shared ID Manager

**Module ID:** `20261108-01`
**Type:** backend · **Language:** go · **Version:** 1.0.0
**Status:** active — supplies shared activity-log IDs and ChenWeb LLM run IDs
**Project:** shared
**Location:** `shared/go/api/idmanager/`
**Created:** 2026-11-08

## 1. What it is

Allocates positive numeric IDs from named counters in PostgreSQL. Use it when
several callers need unique IDs within a shared namespace, or when a caller needs
a contiguous block. Reserving blocks reduces database writes but permits gaps
after restarts. Reusing a finite range intentionally allows duplicates.

## 2. Files

| File | Purpose |
|---|---|
| `shared/go/api/idmanager/manager.go` | Public API, validation, cache and transactions |
| `shared/go/api/idmanager/manager_test.go` | Failure injection and cache/boundary tests |
| `shared/go/api/idmanager/postgres_test.go` | Isolated PostgreSQL migration/concurrency tests |
| `shared/go/api/goose/idmanager_migration.go` | Embeds the schema into shared migration startup |
| `shared/go/api/goose/idmanager_migration_test.go` | Migration availability and conflicting-copy tests |
| `shared/go/api/goose/shared_migrations/20261108000001_id_manager.sql` | Table conversion, constraints and global sequence |

## 3. Interface

Import `github.com/chendingplano/shared/go/api/idmanager`.

- `New(db *sql.DB, requester string) (*Manager, error)` uses an existing pool.
- `(*Manager).Provision(ctx context.Context, seq Sequence) error` inserts or verifies
  bounds and reuse policy. Existing descriptions, sizes and counters are unchanged.
- `(*Manager).Next(ctx context.Context, idName string) (int64, error)` allocates one.
- `(*Manager).Generate(ctx context.Context, idName string, numIDs int64) (Range, error)`
  returns exactly `Range{FirstID, NumIDs}` contiguous IDs.

`Sequence` fields are `Name`, `Desc`, `StartID`, `MaxID`, `AllocateSize`, `AllowReuse`.
`GlobalSequence` is `"global"`. `DefaultMaxID` is 9223372036854775806.
Failures return 0 or `Range{}` and an error. Use `errors.Is` with `ErrInvalidInput`,
`ErrUnknownSequence`, `ErrProvisionConflict`, `ErrExhausted`, `ErrInsufficientRange`,
`ErrDatabase`, `context.Canceled` or `context.DeadlineExceeded`.

## 4. Configuration

These are provisioning defaults; zero numeric fields select the defaults.
The pool and requester are required constructor arguments. There are no TOML keys.

| Key | Default | Meaning |
|---|---|---|
| `StartID` | `1` | Inclusive lower bound |
| `MaxID` | `9223372036854775806` | Inclusive upper bound |
| `AllocateSize` | `1` | Preferred reservation size |
| `AllowReuse` | `false` | Cycle through range; deliberately permits duplicates |

## 5. Usage

After shared migrations have run:

```go
package example

import (
    "context"
    "github.com/chendingplano/shared/go/api/ApiTypes"
    "github.com/chendingplano/shared/go/api/idmanager"
)

func Allocate(ctx context.Context) (idmanager.Range, error) {
    m, err := idmanager.New(ApiTypes.SharedDBHandle, "example-worker")
    if err != nil { return idmanager.Range{}, err }
    if err := m.Provision(ctx, idmanager.Sequence{
        Name: "example_jobs", Desc: "Example job IDs", AllocateSize: 100,
    }); err != nil { return idmanager.Range{}, err }
    return m.Generate(ctx, "example_jobs", 3)
}
```

For a long-lived service, construct the manager once at startup and share it across
callers rather than constructing one per allocation as this small example does.
ChenWeb provisions `llm_run_id` after its project and shared migrations so it
starts above historical usage. Activity logs use `activity_log_id`, provisioned
by `libmanager.InitLib`.

## 6. Behaviour and conventions

The shared Goose runner embeds the migration even when a consuming application's
migration directory lacks a copy. Stop old activity-log writers before applying it:
the old `crt_value` and `caller_loc` columns become `next_id` and `creator`.
Legacy counters advance by 1000 to avoid the old allocator's overlapping block.

Each sequence has a cancellable lock. Refills lock the database row and commit
before publishing a cache block. Failed refills retain the old cache tail. An
uncertain commit publishes nothing. Reservations and failures are logged with
sequence and requester; cache hits are silent.

`global`, `activity_log_id`, and `llm_run_id` cannot enable reuse. Unknown names
are errors. Administrative resets and range/reuse changes while caches exist are
outside the API.

## 7. Scope and limits

PostgreSQL only. Uniqueness applies within one sequence and database when reuse is
off. Gaps and differing delivery order across processes are expected. Audit fields
identify reservations rather than individual cache consumers. The module does not
propagate execution context or track task status.

Tests run with `go test ./api/idmanager` from `shared/go`. For PostgreSQL and race
coverage, set `IDMANAGER_TEST_DSN` to a disposable database named
`idmanager_test_*` and run `go test -race ./api/idmanager ./api/sysdatastores ./api/goose`.
The PostgreSQL suite replaces the ID table and Goose history in that database.

The SQL Down migration preserves counters in the old shape and deliberately keeps
a conservative high-water mark. It refuses rollback if any reusing sequence exists.
Stop all new writers before rollback. Down followed by Up creates additional gaps.

See [the implementation devdoc](../devdocs/202611/2026110801-devdoc-shared-id-manager.md)
for deployment and the ChenWeb integration.

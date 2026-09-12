# Execution Control Flow

## Main Loop

```
initialize(config)
setup_sut(sut_config)       // Reset SUT to known state (assumptions)
state := newStateTracker()
stats := newStats()
startTime := now()

while !shouldStop(stats, config, startTime) {
    // 1. Generate a batch of test cases
    batch := generateBatch(config.batch_size, state)

    // 2. Execute each test case
    for tc in batch {
        // 2a. Run setup commands (C)
        if tc.Setup != nil {
            err := runSetup(tc.Setup)
            if err != nil {
                stats.errors++
                log(tc, "setup_error", err)
                continue
            }
        }

        // 2b. Execute the test (M) with timeout (T)
        result, err := executeWithTimeout(tc.Method, tc.Values, tc.Timeout)

        if err == TIMEOUT {
            stats.failed++
            log(tc, "timeout", nil)
            continue
        }
        if err != nil {
            stats.errors++
            log(tc, "execution_error", err)
            continue
        }

        // 2c. Retrieve results (R)
        actual := retrieveResult(tc.Retrieval, result)

        // 2d. Verify (compare actual vs expected E)
        verdict := verify(actual, tc.Expected)

        if verdict == PASS {
            stats.passed++
        } else {
            stats.failed++
        }

        // 2e. Log
        log(tc, verdict, actual)

        // 2f. Update state tracker
        state.Apply(tc, actual)

        // 2g. Check termination
        if shouldStop(stats, config, startTime) {
            break
        }
    }
}

report(stats)
teardown_sut()
```

## Termination Conditions

```
func shouldStop(stats, config, startTime) -> bool {
    if stats.errors >= config.max_errors {
        return true   // Too many execution errors
    }
    if stats.failed >= config.max_failed {
        return true   // Too many failed test cases
    }
    if elapsed(startTime) >= config.test_dur {
        return true   // Time limit reached
    }
    if stats.total() >= config.num_tcs_to_run {
        return true   // Test case count reached
    }
    return false
}
```

## Verification

Verification compares actual results against expected results at a **semantic level**, not exact string match.

**Approaches (from simple to complex):**

1. **Status code match** - HTTP status, exit code, or boolean pass/fail
2. **Pattern match** - Expected result is a regex or glob pattern
3. **Key field match** - Compare specific fields in structured responses (ignore timestamps, request IDs, etc.)
4. **Semantic match** - Custom comparator that understands domain-specific equivalence

```
func verify(actual, expected) -> verdict {
    // Example: key field match for JSON responses
    actualParsed := parseJSON(actual)

    for key, expectedValue in expected.Fields {
        actualValue := actualParsed[key]
        if !matches(actualValue, expectedValue) {
            return FAIL
        }
    }
    return PASS
}
```

**Non-essential fields to ignore:**
- Timestamps and durations
- Request/correlation IDs
- Server-generated nonces
- Performance metrics

## Logging

### Log Entry Schema

Each test case execution produces a log entry:

```
{
    "torturer": "login-torturer",
    "batch_id": 3,
    "tc_index": 7,
    "timestamp": "2025-01-15T10:30:00Z",
    "seed": 42,
    "operation": "login",
    "parameters": {"email": "test@example.com", "password": "abc123"},
    "expected": {"status": "login_failed", "reason": "user_not_found"},
    "actual": {"status": "login_failed", "reason": "user_not_found"},
    "verdict": "PASS",
    "duration_ms": 45,
    "setup_commands": ["DELETE FROM users"],
    "error": null
}
```

### Storage

Log to the configured database (default: SQLite or PostgreSQL `torturer.test_logs`). Schema:

```sql
CREATE TABLE IF NOT EXISTS test_logs (
    id SERIAL PRIMARY KEY,
    torturer_name TEXT NOT NULL,
    batch_id INTEGER NOT NULL,
    tc_index INTEGER NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    seed BIGINT,
    operation TEXT,
    parameters JSONB,
    expected JSONB,
    actual JSONB,
    verdict TEXT NOT NULL,  -- PASS, FAIL, ERROR, TIMEOUT
    duration_ms INTEGER,
    error TEXT
);
```

## Final Report

After completion, produce a summary:

```
Torturer: login-torturer
Seed: 42
Duration: 95.3s
Total: 100 | Passed: 87 | Failed: 8 | Errors: 3 | Timeouts: 2
Pass Rate: 87.0%
Termination Reason: num_tcs_to_run reached

Failed Test Cases:
  #14: login - expected "user_not_found", got "internal_error"
  #27: signup - expected "success", got "timeout"
  ...
```

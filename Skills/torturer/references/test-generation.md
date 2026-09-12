# Test Case Generation

## Test Case Structure

Each test case: `TC = {C, M, V, R, E, T}`

| Field | Description |
|-------|-------------|
| C | Setup commands to prepare SUT before this test case. May use values from V. Can be empty |
| M | Method/command to execute the test |
| V | Array of `{name, value}` pairs - the parameter values for this test case |
| R | Method to retrieve test results after execution |
| E | Expected result - match pattern, regex, or semantic assertion |
| T | Timeout in seconds. Test fails if not completed within T |

## Generation Strategy

### Step 1: Choose Operation

Randomly select an operation from the SUT's operation set using weighted probabilities. Weight operations by their real-world frequency.

```
operations := []WeightedChoice{
    {Value: "login",          Weight: 50},  // Most common
    {Value: "signup_email",   Weight: 20},
    {Value: "signup_google",  Weight: 10},
    {Value: "forgot_password", Weight: 5},
    // ...
}
```

### Step 2: Generate Parameter Values

For each parameter required by the chosen operation:

1. **Select range**: Use weighted probability to pick a value range
2. **Generate value**: Pick uniformly within the selected range
3. **Apply dependencies**: Ensure dependent parameters are consistent
4. **Tag validity**: Mark whether each value is valid or invalid

```
func generateWeightedValue(ranges []WeightedRange) (value, isValid) {
    // 1. Calculate total weight
    totalWeight := sum(r.Weight for r in ranges)

    // 2. Roll random number in [0, totalWeight)
    roll := random(0, totalWeight)

    // 3. Find the range that matches
    cumulative := 0
    for range in ranges {
        cumulative += range.Weight
        if roll < cumulative {
            // 4. Generate uniformly within this range
            value := uniformRandom(range.Min, range.Max)
            isValid := range.IsValid  // tagged during model definition
            return value, isValid
        }
    }
}
```

### Step 3: Predict Expected Results

This is the critical step. Use the **state tracker** to determine what result to expect.

**Rules for prediction:**

1. **Establish assumptions** - Define the initial state of the SUT (e.g., "empty database", "no users", "default config"). Implement these assumptions as setup steps.

2. **Track state mutations** - After each test case that modifies state (e.g., "create user"), update the state tracker.

3. **Derive expectations from state** - Use current state + parameter validity to predict the result.

**Decision logic example:**

```
func predictResult(operation, params, state) -> expectedResult {
    switch operation {
    case "login":
        if !isValidEmail(params.email) {
            return "invalid email format"
        }
        if !state.userExists(params.email) {
            return "user not found"
        }
        if !state.passwordMatches(params.email, params.password) {
            return "incorrect password"
        }
        return "login success"

    case "signup":
        if !isValidEmail(params.email) {
            return "invalid email format"
        }
        if state.userExists(params.email) {
            return "user already exists"
        }
        // This will mutate state
        state.addUser(params.email, params.password)
        return "signup success"
    }
}
```

### Step 4: Compose the Test Case

Assemble all fields:

- **C (setup)**: Any SUT preparation needed (e.g., clear rate limit counters, set config)
- **M (method)**: The API call, CLI command, or UI action
- **V (values)**: The generated parameter values
- **R (retrieval)**: How to get the result (e.g., parse HTTP response, read stdout)
- **E (expected)**: The predicted result from Step 3
- **T (timeout)**: Appropriate timeout for this operation type

## Batch Generation

Generate test cases in batches, not all at once. This allows:

1. State tracking to remain accurate (earlier test cases affect later predictions)
2. Adaptive generation based on results so far
3. Memory-efficient operation

**Batch flow:**
```
for batch in range(num_batches):
    test_cases := generateBatch(batch_size, current_state)
    results := executeBatch(test_cases)
    updateState(results)
    logResults(results)
    if shouldStop(results):
        break
```

## Mixing Valid and Invalid Cases

A good torturer generates a mix. A suggested default distribution:

| Category | Weight | Description |
|----------|--------|-------------|
| All valid params | 60 | Happy path - all parameters within valid ranges |
| One invalid param | 20 | Single fault - one parameter is invalid |
| Multiple invalid params | 10 | Multi-fault - several parameters are invalid |
| Edge case params | 10 | Boundary values, empty strings, max lengths |

## State Tracker Design

The state tracker must mirror relevant SUT state:

```
type StateTracker struct {
    Users       map[string]UserRecord  // email -> user info
    Sessions    map[string]Session     // active sessions
    RateLimits  map[string]int         // rate limit counters
    // ... other SUT-specific state
}

// Update after each test case execution
func (s *StateTracker) Apply(tc TestCase, result Result) {
    if tc.Operation == "signup" && result.Success {
        s.Users[tc.Params["email"]] = UserRecord{...}
    }
    // ...
}
```

## Reproducibility

Always log the random seed used. Given the same seed and the same SUT state, the same test cases should be generated. This enables:

- Reproducing failures
- Regression testing with the exact same test suite
- Debugging specific test case sequences

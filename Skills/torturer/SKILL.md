---
name: torturer
description: Create automated randomized test harnesses ("torturers") for any System-Under-Test (SUT). Use when the user wants to build an automated testing framework that randomly generates test cases with realistic distributions, executes them against a SUT, and verifies results. Triggers include requests to "torture test", "fuzz test", "create a torturer", "randomized testing", "automated test generation", or building comprehensive automated test suites that go beyond unit tests.
---

# Torturer

Create automated randomized test harnesses for any System-Under-Test (SUT). A torturer treats the SUT as a blackbox, randomly generates test cases that closely simulate real-world usage, executes them, and verifies results automatically.

## Six Design Principles

1. **Test Model** - Model the SUT as parameters with value ranges
2. **Randomness** - All test cases are generated randomly
3. **Closeness** - Random generation follows real-world usage distributions (not uniform)
4. **Verifiability** - Every test case includes expected results; maintain state to predict outcomes
5. **Automation** - End-to-end pipeline: generate, execute, collect, verify, log, repeat
6. **Idempotency** - Same SUT + same test cases = semantically identical results

## Workflow

### Phase 1: Understand the SUT

1. Ask the user what system they want to test
2. Identify or request documentation about the SUT (API docs, CLI usage, UI flows)
3. Identify the SUT's operations (e.g., sign up, login, CRUD operations)
4. Identify the tools/commands/APIs available to interact with the SUT

### Phase 2: Build the Test Model

Build a test model: `TM = {SUT, C, T, P}`. See [references/test-model.md](references/test-model.md) for the full specification.

1. **SUT** - Document the system under test
2. **C (Config)** - Define torturer configuration (max errors, duration, batch size, etc.)
3. **T (Tools)** - Identify commands/APIs/scripts to interact with the SUT
4. **P (Parameters)** - Extract SUT parameters with their valid/invalid value ranges

For each parameter, define:
- Name and type
- Valid value range with weighted probability distribution (closeness principle)
- Invalid values and edge cases
- Dependencies on other parameters

### Phase 3: Generate Test Cases

Each test case: `TC = {C, M, V, R, E, T}`. See [references/test-generation.md](references/test-generation.md) for generation patterns.

- **C**: Setup commands to prepare the SUT
- **M**: Method to execute the test
- **V**: Parameter name-value pairs
- **R**: Method to retrieve results
- **E**: Expected result (match pattern or regex)
- **T**: Timeout in seconds

Key rules:
- Generate values using weighted random distributions, not uniform random
- Track SUT state during generation to predict expected results accurately
- Include both valid and invalid parameter combinations
- Establish assumptions (e.g., "start with empty database") that enable predictable outcomes

### Phase 4: Implement the Torturer

Generate code that implements:

1. **Config loader** - Parse torturer config (name, log settings, max errors, duration, etc.)
2. **Parameter generators** - Weighted random generators for each SUT parameter
3. **State tracker** - Track what has happened in the SUT to predict future outcomes
4. **Test case generator** - Compose parameters into full test cases with expected results
5. **Test executor** - Run test cases with timeout enforcement
6. **Result collector** - Retrieve and normalize actual results
7. **Verifier** - Compare actual vs expected results (semantic comparison, not exact match)
8. **Logger** - Log all activities, results, and verdicts
9. **Controller** - Orchestrate the pipeline with termination conditions

See [references/control-flow.md](references/control-flow.md) for execution control flow.

### Phase 5: Run and Report

1. Execute the torturer against the SUT
2. Collect pass/fail statistics
3. Report failures with full context (test case, expected, actual, SUT state)
4. Determine if testing should continue or stop (based on max_errors, max_failed, test_dur, num_tcs_to_run)

## Language Choice

Default to the language of the SUT's ecosystem. For HTTP APIs, prefer Go or Python. For CLI tools, prefer bash + Go/Python. Always ask the user if they have a preference.

## Weighted Random Generation Pattern

Use weighted probability distributions to simulate real-world usage:

```
// Example: username length distribution
ranges := []WeightedRange{
    {Min: 3, Max: 15, Weight: 100},  // Normal: most common
    {Min: 1, Max: 2, Weight: 5},     // Edge: very short
    {Min: 16, Max: 30, Weight: 40},  // Less common but valid
    {Min: 31, Max: 64, Weight: 15},  // Rare but valid
    {Min: 65, Max: 128, Weight: 5},  // Very rare
    {Min: 129, Max: 256, Weight: 2}, // Invalid territory
}
```

Pick a range by weighted probability, then pick uniformly within that range.

## Example

For a complete worked example (Login SUT), see [references/example-login.md](references/example-login.md).

## Output Structure

A torturer project should produce:

```
torturer-<sut-name>/
  config.yaml          # Torturer configuration
  sut.md               # SUT documentation
  tools.md             # Tools/APIs documentation
  main.<ext>           # Entry point
  generator.<ext>      # Test case generation with weighted random
  executor.<ext>       # Test execution with timeout
  verifier.<ext>       # Result verification
  state.<ext>          # SUT state tracking
  logger.<ext>         # Logging to database/file
```

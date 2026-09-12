# Test Model Specification

## Definition

A Test Model is defined as: `TM = {SUT, C, T, P}`

| Component | Description |
|-----------|-------------|
| SUT | The system under test (blackbox) |
| C | Torturer configuration |
| T | Tools, commands, and APIs to interact with the SUT |
| P | Parameters `[p1, p2, ..., pn]` that control SUT behavior |

## SUT Documentation

Document the SUT in a `sut.md` file covering:
- What the system does
- Its operations/endpoints/commands
- Authentication requirements
- State management (database, files, etc.)
- Known constraints and limits

## Configuration (C)

| Config Item | Default | Description |
|-------------|---------|-------------|
| torturer_name | (required) | Unique name for this torturer |
| log_level | "full" | Logging verbosity. Currently only "full" supported |
| log_dbname | "torturer" | Database name for test logs |
| log_tablename | "test_logs" | Table name for test logs |
| max_errors | 10 | Max execution errors before termination |
| max_failed | 10 | Max failed test cases before termination |
| test_dur | 100 | Test duration in seconds |
| num_tcs_to_run | 100 | Number of test cases to run |
| sut_config | "./sut_config" | Path to SUT configuration. Set to "none" if SUT needs no config |
| batch_size | 10 | Number of test cases per batch |
| seed | (random) | Random seed for reproducibility |

When both `test_dur` and `num_tcs_to_run` are set, testing stops at whichever limit is reached first.

## Tools (T)

Document all tools required to interact with the SUT in a `tools.md` file:

- CLI commands and their flags
- API endpoints (method, URL, headers, body format)
- Database queries for state verification
- Setup/teardown scripts

Each tool entry should include:
- Name and purpose
- Invocation syntax
- Expected input/output format
- Error conditions

## Parameters (P)

### Extracting Parameters

Analyze each SUT operation to extract parameters. A parameter is anything that:
- Is provided as input to the SUT
- Controls SUT behavior
- Affects the outcome of an operation

### Parameter Definition

Each parameter must define:

```yaml
parameter:
  name: "username"
  type: "string"          # string, integer, float, boolean, enum, composite
  operations: ["signup", "login"]  # Which operations use this parameter
  required: true
  constraints:
    charset: "a-zA-Z0-9_.-"
    min_length: 1
    max_length: 128
  weighted_ranges:
    - range: [3, 15]
      weight: 100
      label: "Normal usage"
    - range: [1, 2]
      weight: 5
      label: "Very short, edge case"
    - range: [16, 30]
      weight: 40
      label: "Longer than usual"
    - range: [31, 64]
      weight: 15
      label: "Rare but valid"
    - range: [65, 128]
      weight: 5
      label: "Very rare"
    - range: [129, 256]
      weight: 2
      label: "Invalid - exceeds max"
  invalid_generators:
    - type: "empty"           # Empty string
    - type: "null"            # Null/nil value
    - type: "wrong_charset"   # Characters outside allowed charset
    - type: "overflow"        # Exceeds max length
```

### Parameter Dependencies

Some parameters depend on others. Document dependencies explicitly:

```yaml
dependencies:
  - parameter: "password_confirm"
    depends_on: "password"
    relationship: "must_match"    # For valid cases
  - parameter: "email"
    depends_on: "operation"
    relationship: "required_when"
    condition: "operation in ['signup_email', 'login_email', 'forgot_password']"
```

### Value Range Types

| Type | Description | Example |
|------|-------------|---------|
| Numeric range | Min/max with weighted sub-ranges | Timeout: [1, 300] |
| String pattern | Charset + length with weighted ranges | Username: alphanumeric, [1, 128] |
| Enum | Fixed set of values with weights | Operation: signup_email (30), login (50), ... |
| Boolean | true/false with weights | Remember me: true (70), false (30) |
| Composite | Structured type built from sub-parameters | Address: {street, city, zip} |

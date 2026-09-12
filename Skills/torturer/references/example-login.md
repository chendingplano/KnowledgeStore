# Example: Login Module Torturer

A complete worked example of building a torturer for a Login module SUT.

## SUT Description

The Login module supports:
1. Sign up with email
2. Sign up with Google
3. Sign up with GitHub
4. Sign up with username and password
5. Login with email and password
6. Login with Google
7. Login with GitHub
8. Forgot password

## Test Model

### Parameters

| Parameter | Type | Operations | Valid Range |
|-----------|------|------------|-------------|
| operation | enum | all | One of the 8 operations above |
| email | string | 1, 5, 8 | Valid email format, [5, 254] chars |
| username | string | 4 | Alphanumeric + `_.-`, [1, 128] chars |
| password | string | 1, 4, 5 | Any printable chars, [8, 128] chars |
| oauth_token | string | 2, 3, 6, 7 | Valid OAuth token format |
| url | string | all | Valid URL format |
| timeout | integer | all | [1, 300] seconds |

### Weighted Ranges

**Operation distribution:**
```yaml
- value: "login_email"      weight: 40   # Most common
- value: "signup_email"      weight: 20
- value: "login_google"      weight: 15
- value: "login_github"      weight: 8
- value: "signup_google"     weight: 5
- value: "signup_github"     weight: 5
- value: "signup_username"   weight: 4
- value: "forgot_password"   weight: 3
```

**Email length distribution:**
```yaml
- range: [5, 30]    weight: 100  # Normal emails
- range: [31, 64]   weight: 30   # Longer but valid
- range: [65, 128]  weight: 10   # Rare
- range: [129, 254] weight: 5    # Very long
- range: [1, 4]     weight: 3    # Too short (invalid)
- range: [255, 500] weight: 2    # Exceeds max (invalid)
```

**Password length distribution:**
```yaml
- range: [8, 20]    weight: 100  # Common passwords
- range: [21, 40]   weight: 30   # Strong passwords
- range: [41, 128]  weight: 10   # Very long
- range: [1, 7]     weight: 8    # Too short (invalid)
- range: [129, 256] weight: 2    # Exceeds max (invalid)
```

### Config

```yaml
torturer_name: "login-torturer"
log_level: "full"
log_dbname: "torturer"
log_tablename: "test_logs"
max_errors: 10
max_failed: 20
test_dur: 300
num_tcs_to_run: 500
sut_config: "./login_sut_config.yaml"
batch_size: 10
seed: 42
```

## State Tracker

```go
type LoginState struct {
    Users map[string]UserRecord // email/username -> record
}

type UserRecord struct {
    Email    string
    Username string
    Password string
    Provider string // "email", "google", "github"
}
```

## Test Case Generation Example

**Assumptions:** SUT starts with an empty database (no users).

### Generated Batch (10 test cases):

| # | Operation | Key Params | Expected | Reasoning |
|---|-----------|-----------|----------|-----------|
| 1 | login_email | email="alice@test.com", pass="secret123" | FAIL: user not found | No users exist yet |
| 2 | signup_email | email="bob@test.com", pass="mypass456" | SUCCESS | Valid params, email not taken |
| 3 | signup_email | email="bob@test.com", pass="other789" | FAIL: email exists | bob@test.com was just created in #2 |
| 4 | login_email | email="bob@test.com", pass="wrong" | FAIL: wrong password | User exists but password wrong |
| 5 | login_email | email="bob@test.com", pass="mypass456" | SUCCESS | Correct credentials from #2 |
| 6 | signup_email | email="x", pass="short" | FAIL: invalid email | Email too short, invalid format |
| 7 | forgot_password | email="nobody@test.com" | FAIL: user not found | Email not in database |
| 8 | forgot_password | email="bob@test.com" | SUCCESS | bob@test.com exists from #2 |
| 9 | signup_username | username="charlie", pass="pass1234" | SUCCESS | Valid, username not taken |
| 10 | login_email | email="bob@test.com", pass="mypass456" | SUCCESS | Still valid from #2 |

Notice how the state tracker enables accurate predictions:
- Test #3 knows bob@test.com exists because #2 succeeded
- Test #5 knows the correct password because the tracker recorded it from #2
- Test #8 knows the email exists in the database

## Verification Rules

```go
func verifyLogin(actual, expected Result) Verdict {
    // Compare status (success/fail)
    if actual.Status != expected.Status {
        return FAIL
    }
    // For failures, compare reason category
    if actual.Status == "fail" {
        if actual.ReasonCode != expected.ReasonCode {
            return FAIL
        }
    }
    // Ignore: response time, session token value, request ID
    return PASS
}
```

## Tools (T)

```yaml
tools:
  - name: "signup_api"
    method: POST
    url: "{{base_url}}/api/auth/signup"
    body: '{"email": "{{email}}", "password": "{{password}}"}'
    headers:
      Content-Type: "application/json"
    success_status: 201

  - name: "login_api"
    method: POST
    url: "{{base_url}}/api/auth/login"
    body: '{"email": "{{email}}", "password": "{{password}}"}'
    headers:
      Content-Type: "application/json"
    success_status: 200

  - name: "reset_db"
    type: "command"
    command: "psql -d {{db_name}} -c 'TRUNCATE users CASCADE'"
    purpose: "Reset SUT to empty state (assumption enforcement)"
```

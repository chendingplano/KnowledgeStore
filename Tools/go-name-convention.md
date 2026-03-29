# Go Naming Conventions — Quick Reference

Source: Alex Edwards, “Go Naming Conventions: A Practical Guide” (March 24, 2026)  
https://www.alexedwards.net/blog/go-naming-conventions \
Date: 2026/03/28 \
Creator: Codex

## 1) Identifier Basics

Hard rules:
- Use only letters, digits, and `_`.
- Do not start with a digit.
- Do not use Go keywords.

Style:
- Unexported: `camelCase`
- Exported: `PascalCase`
- Avoid: `snake_case`, `SCREAMING_SNAKE_CASE`, random caps.

Quick definitions:
| Style | Explanation |
|:------|:------------|
| `camelCase` | Start lowercase and capitalizes later words (`userID`) |
| `PascalCase` | Capitalize every word (`UserID`) |
| `snake_case` | Use separators between lowercase words (`user_id`) |
| `SCREAMING_SNAKE_CASE` | Use uppercase words separated by underscores (`MAX_RETRIES`) |
| `random caps` | Inconsistent capitalization with no rule (`uSeRiD`) |
--------

## 2) Go Keywords

`break`, `default`, `func`, `interface`, `select`, `case`, `defer`, `go`, `map`, `struct`, `chan`, `else`, `goto`, `package`, `switch`, `const`, `fallthrough`, `if`, `range`, `type`, `continue`, `for`, `import`, `return`, `var`

## 3) Acronyms, Initialisms, and `ID`

- Keep acronym casing consistent.
- Prefer `apiKey` / `APIKey`, not `ApiKey`.
- Prefer `userID`, not `userId`.
- Prefer `HTTPClient`, `parseXML`, `sessionID`.

## 4) Exporting Rules

- Capitalized first letter means exported.
- Default to unexported unless cross-package use is needed.
- In `main` packages, most identifiers should usually remain unexported.

## 5) Length and Clarity

Rule of thumb:
- Smaller scope / close usage: shorter names are fine (`i`, `p`).
- Wider scope / farther usage: use more descriptive names (`count`, `sum`, `orderTotal`).
- Don’t over-verbose local names.

## 6) Avoid Common Naming Pitfalls

- Avoid non-ASCII identifiers unless there is a strong reason.
- Avoid clashing with builtins (`int`, `len`, `min`, `max`, `clear`).
- Avoid clashing with imported package names in the same file.
- Usually avoid embedding type names in identifiers (`resultSlice`, `amountFloat64`) unless needed to distinguish converted values (e.g., `userID` -> `userIDStr`).

## 7) Package Naming

Conventions:
- Lowercase ASCII letters + digits only.
- Keep names short and meaningful.
- Prefer one-word nouns (`orders`, `slug`, `customer`).
- For multiword names, use lowercase concatenation (`ordermanager`).
- Abbreviate if needed (`ordermgr`) when length hurts readability.

Avoid:
- Leading `.` or `_` (ignored by Go tooling).
- Names with special Go meaning: `vendor`, `testdata`, `internal`.
- Catch-all names (`common`, `util`, `helpers`, `types`, `interfaces`).
- Common stdlib package names if avoidable (`url`, `mail`, `json`, `time`, etc.).

## 8) File Naming (`.go` files)

- Prefer lowercase, descriptive filenames.
- One word is ideal (`server.go`, `cookie.go`).
- If multiword, pick one style and stay consistent:
  - `routingindex.go` or
  - `routing_index.go`

Special filenames/suffixes:
- Leading `.` or `_` -> ignored by Go tools.
- `_test.go` -> test-only files.
- OS/arch suffixes (e.g., `_linux.go`, `_windows.go`, `_amd64.go`) control build inclusion.

## 9) Avoid “Chatter” at Call Sites

Don’t repeat package/type names unnecessarily.

Prefer:
- `customer.New()` over `customer.NewCustomer()`
- `customer.Orders()` over `customer.CustomerOrders()`
- `customer.Address` over `customer.CustomerAddress`

Note: `time.Time`, `context.Context`, and similar are common and acceptable.

## 10) Method Receivers

- Use short receiver names (typically 1–3 chars), often an abbreviation.
- Be consistent for all methods on the same type.
- Avoid generic receiver names like `this`, `self`, `me`.

Example:
- Good: `func (o *Order) Validate() bool`
- Avoid: `func (order *Order) Validate() bool`, `func (self *Order) Validate() bool`

## 11) Getters and Setters

In Go, direct struct field access is preferred when possible.

When fields are unexported but external access is needed:
- Getter: use field-style name, no `Get` prefix (`Address()`)
- Setter: use `Set` prefix (`SetAddress(...)`)

## 12) Interface Naming

- Single-method interfaces are commonly method + `-er` (or similar):
  - `Reader`, `Writer`, `Stringer`, `Authenticator`
- Avoid placeholder names like `UserInterface` / `OrderInterface` unless unavoidable.

## 13) Practical Checklist

Before committing, quickly check:
- [ ] Exported vs unexported casing is intentional.
- [ ] Acronyms and `ID` are consistently cased.
- [ ] No collisions with builtins or imported package names.
- [ ] Package names are short, focused, and non-generic.
- [ ] Filenames follow one consistent convention.
- [ ] Receiver names are short and consistent.
- [ ] No unnecessary chatter in public APIs.
- [ ] Interface names are meaningful (often `-er` for single-method interfaces).

## 14) When to Break Convention

Rarely, breaking convention can improve clarity (for example, mirroring external system names in integration code). If you break convention, do it deliberately and consistently.

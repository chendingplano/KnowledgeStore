# ADR 2026072001 — User Roles in Kratos via `metadata_public.roles`

**Date:** 2026-07-20 \
**Status:** Proposal \
**Component:** Shared auth (`shared/go`), Kratos identities, ChenWeb, tax \
**Authors**: Codex

## Change Logs
* 2026/07/20, ADR created.

## Context

ChenWeb and other projects in this workspace authenticate through Ory Kratos,
with the main shared integration implemented in
`shared/go/api/auth/kratos.go`. Today, authorization data in the shared path is
very limited:

- users are identified internally by Kratos identity id
- email is the main human-facing lookup key
- admin is represented as `metadata_public.admin` -> `UserInfo.Admin`
- owner is represented as `metadata_public.is_owner` -> `UserInfo.IsOwner`

This is enough for existing boolean checks such as "admin or owner", but it is
not enough for the planned page-content access-control model, where access is
driven by membership in named roles (`kb.page_config.access_role`).

The code review for this ADR found an additional inconsistency:

- the shared auth path uses `metadata_public.admin` as the effective admin
  source of truth
- the sample middleware in `Kratos/backend/main.go` checks
  `metadata_admin.role == "admin"`

No shared authorization layer currently reconciles these two conventions.

At the same time, backward compatibility is mandatory:

- an existing production project depends on the `admin` flag and it must not be
  removed
- `tax/` depends on `is_owner`, and it must continue to function
- user identification by Kratos identity id and email should remain unchanged

## Decision

### DR1 — Keep user identification unchanged

Do not change the current user-identification model.

- Kratos identity id remains the canonical internal user identifier.
- Email remains the primary operator-facing lookup key where needed.
- Shared APIs that resolve users by identity id or email continue to do so.

User roles are an authorization change, not an identity-key redesign.

### DR2 — Store application roles in `metadata_public.roles`

The canonical application role store is Kratos identity
`metadata_public.roles`, represented as a JSON array of strings.

Example:

```json
{
  "admin": true,
  "is_owner": false,
  "roles": ["admin", "k_engineer"]
}
```

This is chosen because:

- the shared auth path already reads and writes `metadata_public`
- current application-facing compatibility fields already live there
  (`admin`, `is_owner`, `avatar`, app tokens)
- it avoids introducing a second application authorization source of truth

`metadata_admin` may still exist for privileged Kratos-side metadata, but it is
not the canonical role store for shared application authorization.

### DR3 — `admin` is a role, but the boolean flag stays

Conceptually, `admin` is just a role. However, for full backward
compatibility:

- if a user has role `admin`, the `admin` flag must be set accordingly
- existing code reading `UserInfo.Admin` must continue to work
- existing code reading `metadata_public.admin` must continue to work

The long-term source of truth becomes role membership, while the boolean admin
field remains a required compatibility projection.

### DR4 — Keep `is_owner` as a backward-compatible compatibility field

`is_owner` remains supported as a separate boolean because existing projects,
especially `tax/`, depend on it.

However:

- new authorization design should not introduce new dependencies on `is_owner`
- new projects, including ChenWeb, should use roles instead of `is_owner`

### DR5 — Add roles to the shared user model and auth responses

`shared/go/api/ApiTypes/ApiTypes.go::UserInfo` will gain:

```go
Roles []string `json:"roles"`
```

The shared auth layer will populate this field from `metadata_public.roles`.
`HandleAuthMeKratos` and related shared auth responses should surface roles as
part of the authenticated user representation.

### DR6 — Shared auth reads roles from `metadata_public.roles` and derives compatibility fields

Both current identity-read paths must be updated:

- `extractIdentityInfo(...)`
- `KratosIdentityToUserInfo(...)`

They will:

- read `metadata_public.roles`
- normalize the role list
- populate `UserInfo.Roles`
- derive `UserInfo.Admin` from the role list, while still honoring the legacy
  boolean during migration/backfill
- continue to populate `UserInfo.IsOwner` from `metadata_public.is_owner`

### DR7 — Role management must be implemented in `shared/go`

Role-management helpers and APIs should be implemented in `shared/go`, not as
project-local one-offs.

This includes:

- shared identity-update helpers for roles
- normalization and validation of role names
- compatibility projection logic for `admin`
- shared authorization helpers that test role membership

### DR8 — Initial role catalog

The initial canonical role catalog is:

- `admin`
- `root`
- `guest`
- `dev`
- `k_engineer`
- `trial`

Notes:

- role names use lowercase snake_case
- `root` is reserved now but not intended for active use yet
- the catalog may grow later, but these names are the initial baseline

## Alternative Decisions

- Store roles in `traits` — rejected. Roles are authorization metadata, not
  identity traits, and the current Kratos schema does not define them there.
- Store roles in `metadata_admin` — rejected for shared application use. The
  shared auth path already standardizes on `metadata_public`, and switching to
  `metadata_admin` would create a breaking divergence for existing projects.
- Remove `admin` and `is_owner` immediately — rejected. Existing production
  consumers require full backward compatibility.
- Introduce a separate SQL role store outside Kratos — rejected for now.
  Kratos identity metadata is already the canonical identity record and is
  sufficient for this authorization layer.

## Implementation

### Code Changes

- `shared/go/api/ApiTypes/ApiTypes.go`
  - add `Roles []string` to `UserInfo`
- `shared/go/api/auth/kratos.go`
  - extend `identityInfo` with roles
  - update `extractIdentityInfo(...)` to parse `metadata_public.roles`
  - update `KratosIdentityToUserInfo(...)` to parse `metadata_public.roles`
  - add shared role normalization / derivation helpers
  - preserve compatibility reads for `metadata_public.admin`
- `shared/go/api/auth/authme.go`
  - ensure authenticated responses include roles through `UserInfo`
- `shared/go/api/EchoFactory/echo_factory.go`
  - extend the user update path so roles can be written through Kratos identity
    updates
  - when writing roles, maintain `metadata_public.admin` in sync with presence
    or absence of role `admin`
  - preserve `metadata_public.is_owner` unless explicitly changed by a
    backward-compatible caller
- `shared/go/api/handlers/users_handler.go` and other authorization call sites
  - continue working with `Admin bool`
  - new authorization code should prefer shared role helpers

### Data Format

Kratos identity `metadata_public`:

```json
{
  "admin": true,
  "is_owner": false,
  "roles": ["admin", "dev"]
}
```

Rules:

- `roles` is an array of canonical lowercase snake_case strings
- duplicate roles are removed on write/read normalization
- `admin` is projected from presence of role `admin`
- `is_owner` remains an independent compatibility field

### Migration Plan

1. Add `Roles []string` to the shared user model and auth responses.
2. Add role parsing to the shared Kratos identity readers.
3. Add shared role-update helpers in `shared/go`.
4. Backfill `metadata_public.roles` for users that currently rely on boolean
   `admin`.
5. Keep `metadata_public.admin` synchronized with role `admin`.
6. Migrate new authorization logic to shared role helpers.
7. Stop depending on `metadata_admin.role` for shared app authorization.

### Backward Compatibility Requirements

- Do not remove `metadata_public.admin`.
- Do not remove `metadata_public.is_owner`.
- Do not remove `UserInfo.Admin`.
- Do not remove `UserInfo.IsOwner`.
- Do not change user identification by Kratos identity id and email.
- Existing production projects must continue to function without requiring
  immediate authorization rewrites.

## Consequences

### Positive

- The system gains a first-class role model that supports page-level access
  control.
- Kratos remains the single identity store, with no parallel role database.
- Shared authorization becomes more expressive without changing user identity
  semantics.
- Existing projects keep working through compatibility projections.

### Negative / accepted costs

- Shared auth must carry dual semantics during migration: canonical role list
  plus compatibility booleans.
- Some code paths will need careful review to ensure they stop assuming admin is
  only a boolean.
- The mismatch between `metadata_public.admin` and `metadata_admin.role` will
  remain in the repo until all shared authorization code is migrated to the new
  convention.

## References

- [2026072002 — ChenWeb User Management via Kratos with Self-Scoped Access](./2026072002-adr-user-management-chenweb.md)
- [2026072002 — Spec: User Roles in Kratos and Shared Auth](../specs/202607/2026072002-spec-user-roles-kratos.md)
- `shared/go/api/auth/kratos.go`
- `shared/go/api/auth/authme.go`
- `shared/go/api/EchoFactory/echo_factory.go`
- `shared/go/api/ApiTypes/ApiTypes.go`
- `shared/go/api/handlers/users_handler.go`
- `Kratos/kratos/identity.schema.json`
- `Kratos/backend/main.go`

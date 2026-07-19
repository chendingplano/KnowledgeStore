# User Roles in Kratos Implementation

**Date:** 2026-07-20 \
**Status:** Implemented \
**Component:** `shared/` auth integration, Kratos-backed user model \
**Authors**: Codex \

## Change Logs
* 2026/07/20, Document created.

## Purpose

This document records the implementation completed for the user-role work
described by:

- ADR 2026072001 — `user-roles-kratos`
- Spec 2026072002 — `user-roles-kratos`

It focuses on:

- what was implemented in code
- what compatibility behavior was preserved
- what was verified
- what was intentionally not changed yet

## Summary

The implementation adds first-class role support to the shared Kratos
integration while preserving the existing `admin` and `is_owner` compatibility
model.

The key outcome is:

- Kratos identities can now carry `metadata_public.roles`
- shared Go auth code reads those roles into `UserInfo.Roles`
- legacy `admin` behavior remains intact
- if a user has role `admin`, the effective admin flag remains `true`
- if an older identity only has `metadata_public.admin = true`, the shared auth
  layer projects that into the effective role list as `admin`

This keeps the system backward compatible for existing production consumers
while making role-based authorization possible for new work.

## Implementation Scope

The implementation was made in `shared/` on branch:

- `feat/user-roles-kratos`

Committed as:

- `a2fc566` — `Add Kratos role compatibility support`

The work was intentionally scoped to `shared/`. `Kratos/` itself was not
modified as part of this implementation.

## Main Code Changes

### 1. Shared user model now carries roles

File:

- `shared/go/api/ApiTypes/ApiTypes.go`

Implemented change:

- added `Roles []string` to `ApiTypes.UserInfo`

This makes roles available in the standard shared request/user model without
removing or renaming any existing fields.

Backward compatibility preserved:

- `UserInfo.Admin` remains unchanged
- `UserInfo.IsOwner` remains unchanged

### 2. Added role normalization and projection helpers in auth

File:

- `shared/go/api/auth/roles.go`

Implemented behavior:

- normalize role names to lowercase snake_case-like values
- ignore invalid or empty role entries
- deduplicate role entries
- sort normalized role lists for stable comparison
- project legacy `admin` into the role list when needed

Important compatibility rule implemented:

- if `metadata_public.admin == true` and `roles` is absent, the effective role
  list includes `admin`

This ensures older identities can still satisfy future role-based checks before
they are backfilled.

### 3. Kratos identity reads now populate `Roles`

File:

- `shared/go/api/auth/kratos.go`

Implemented change:

- extended `identityInfo` with `Roles`
- updated `extractIdentityInfo(...)`
- updated `KratosIdentityToUserInfo(...)`

New read behavior:

- read `metadata_public.roles`
- normalize the role list
- derive effective admin state from roles and legacy admin flag
- preserve `is_owner`

Compatibility behavior:

- `admin` still works for legacy callers
- `roles` and `admin` now agree semantically in shared auth code

### 4. Shared update path now keeps `roles` and `admin` consistent

Files:

- `shared/go/api/EchoFactory/roles.go`
- `shared/go/api/EchoFactory/echo_factory.go`

Implemented change:

- added shared helper logic to resolve updated roles from:
  - existing roles
  - optional requested roles
  - legacy boolean `admin`
- when updates are written, `metadata_public.admin` is kept in sync with the
  presence or absence of role `admin`

Compatibility behavior:

- old callers that only reason about `admin bool` continue to work
- new callers can provide `Roles`
- `is_owner` is preserved as an independent compatibility field

### 5. Kratos-auth response payloads now include roles

Files:

- `shared/go/api/auth/kratos.go`
- `shared/svelte/src/lib/stores/auth.svelte.ts`
- `shared/svelte/src/lib/types/CommonTypes.ts`

Implemented change:

- added `roles` to the frontend-facing shared `UserInfo` type
- updated the Svelte auth store’s Kratos identity mapping to carry
  `metadata_public.roles`
- updated manual session/auth response payload construction in `kratos.go` to
  include `roles`

This ensures the new field is not only stored in Go, but is also propagated to
shared client consumers.

### 6. Signup/session projection for admin users

File:

- `shared/go/api/auth/kratos.go`

Implemented change:

- added a helper to project signup-time admin state into a compatible role list

Current behavior:

- admin signup/session payloads include `roles: ["admin"]`
- non-admin signup/session payloads include an empty role list

## Tests Added

### Auth package tests

File:

- `shared/go/api/auth/kratos_roles_test.go`

These tests verify:

- roles are normalized and deduplicated
- admin is derived from roles
- legacy `admin=true` is projected into the effective role list
- `KratosIdentityToUserInfo(...)` reads roles and preserves compatibility flags

### EchoFactory tests

File:

- `shared/go/api/EchoFactory/echo_factory_roles_test.go`

These tests verify:

- existing roles are preserved
- legacy admin updates add/remove role `admin` correctly
- explicit roles and legacy admin compatibility are reconciled consistently

## Verification

Verified in the implementation branch/worktree with:

```bash
cd shared/go
go test ./api/auth ./api/EchoFactory
```

Result:

- passed

Additional TypeScript check attempted:

```bash
cd shared/svelte
bun x tsc --noEmit
```

Result:

- failed due pre-existing workspace/dependency/type-check issues unrelated to
  this change, including missing module/type declarations and existing Svelte
  `$state` typing/runtime issues

No new TypeScript-specific failure attributable to the added `roles` field was
isolated from those pre-existing issues during this run.

## What Was Not Changed

The following were intentionally not changed in this implementation:

### 1. `Kratos/backend/main.go`

The sample Kratos backend still contains its separate
`metadata_admin.role == "admin"` middleware logic.

This implementation does **not** reconcile that code path. The implemented
standardization happened only in `shared/`.

### 2. `is_owner` semantics

`is_owner` remains a separate compatibility field.

This implementation does not convert it into a role and does not change any
existing owner-based authorization behavior.

### 3. Dedicated role-management APIs

The implementation adds shared read/update compatibility logic, but it does not
yet add a dedicated role-management API surface for administration.

### 4. Role-based authorization helpers across the whole codebase

This implementation prepares the data model and shared auth layer, but it does
not yet refactor all downstream authorization call sites to use role membership
directly.

Existing `Admin bool` checks still remain valid and intentionally supported.

## Operational Behavior After This Change

After this implementation:

- a Kratos identity may carry `metadata_public.roles`
- shared auth returns those roles in `UserInfo.Roles`
- old identities with only `metadata_public.admin = true` still behave as admin
- writes through the shared user-update path keep `admin` and role `admin`
  aligned

Example effective metadata shape:

```json
{
  "admin": true,
  "is_owner": false,
  "roles": ["admin", "dev"]
}
```

## Consequences

### Positive

- shared auth now supports first-class roles
- backward compatibility for existing production projects is preserved
- future page-level role-based access control can build on `UserInfo.Roles`
- the shared data path now has a canonical application role location:
  `metadata_public.roles`

### Negative / accepted limitations

- dual semantics remain for now: role list plus compatibility booleans
- the sample Kratos backend still reflects a different admin convention
- broader role-management/admin tooling remains future work

## References

- [2026072002-spec-user-roles-kratos.md](../../specs/202607/2026072002-spec-user-roles-kratos.md)
- [2026072001-adr-user-roles-kratos.md](../../adrs/202607/2026072001-adr-user-roles-kratos.md)
- `shared/go/api/ApiTypes/ApiTypes.go`
- `shared/go/api/auth/kratos.go`
- `shared/go/api/auth/roles.go`
- `shared/go/api/auth/kratos_roles_test.go`
- `shared/go/api/EchoFactory/echo_factory.go`
- `shared/go/api/EchoFactory/roles.go`
- `shared/go/api/EchoFactory/echo_factory_roles_test.go`
- `shared/svelte/src/lib/types/CommonTypes.ts`
- `shared/svelte/src/lib/stores/auth.svelte.ts`

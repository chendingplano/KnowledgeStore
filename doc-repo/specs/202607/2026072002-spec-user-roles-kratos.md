# Spec: User Roles in Kratos and Shared Auth

Date: 2026-07-20

Status: **Proposed**

References:
- Spec: [2026072001 — Page Content Configurability and i18n Pattern](./2026072001-spec-page-content-configurability-i18n.md)
- Kratos identity schema: `Kratos/kratos/identity.schema.json`
- Shared auth integration: `shared/go/api/auth/kratos.go`
- Shared auth response path: `shared/go/api/auth/authme.go`
- Shared request context / user update path: `shared/go/api/EchoFactory/echo_factory.go`
- Shared user type: `shared/go/api/ApiTypes/ApiTypes.go`
- Kratos sample backend admin middleware: `Kratos/backend/main.go`

## 1. Overview

ChenWeb and the shared Go library currently support authentication through Ory
Kratos, but they do not yet have a first-class user-role model. The current
implementation effectively supports only:

- authenticated vs unauthenticated users
- a boolean admin flag
- a boolean owner flag

This is sufficient for simple admin-only checks, but it is not sufficient for
the planned page-level access-control model described in
`2026072001-spec-page-content-configurability-i18n.md`, where access is
granted by membership in one or more named roles.

This spec documents:

- the current implementation
- the current gaps and inconsistencies
- the planned role model
- the storage and API changes needed to support it

## 2. Goals

- Introduce first-class user roles for Kratos-backed identities.
- Reuse Kratos identity JSON metadata instead of creating a parallel role store
  outside Kratos.
- Preserve full backward compatibility with the current `admin`-based and
  `is_owner`-based checks during migration and after rollout.
- Provide a canonical server-side source of truth for authorization.
- Support future page-content access control driven by role membership.

## 3. Non-Goals

- Replacing Kratos as the identity system.
- Designing the full organization-wide role catalog in this document.
- Moving authorization decisions to the frontend.
- Removing the existing `admin` flag immediately.

## 4. Current Implementation

### 4.0 User identification today

In the current Kratos-based implementation, users are identified primarily by:

- Kratos identity id
- email address as the main human-facing identifier and lookup key

Current usage patterns:

- session validation resolves the active Kratos session and identity
- user lookup APIs use identity id or email
- `KratosGetIdentityByID(...)` resolves by identity id
- `KratosGetIdentityByEmail(...)` resolves by email using
  `credentials_identifier`
- `ApiTypes.UserInfo.UserId` stores the Kratos identity id
- `ApiTypes.UserInfo.Email` stores the current email address

This spec does **not** propose changing the user identification model.

Decision:

- Kratos identity id remains the canonical internal user identifier
- email remains the primary operator-facing lookup key where needed

Rationale:

- this matches the current implementation
- it avoids unnecessary migration risk
- roles are an authorization concern, not an identity-key redesign

Any future change to user identification would need to remain fully backward
compatible with the existing identity-id and email-based lookup paths.

### 4.1 Kratos identity schema

The Kratos identity schema at `Kratos/kratos/identity.schema.json` defines only
`traits`, primarily:

- `email`
- `username`
- `name.first`
- `name.last`

It does not define roles as a first-class trait.

That is acceptable because Kratos identities also support JSON metadata fields,
including `metadata_public` and `metadata_admin`, which can carry additional
application-specific authorization data.

### 4.2 Shared auth path today

The shared auth integration in `shared/go/api/auth/kratos.go` currently
extracts user-facing authorization flags from `metadata_public`, not from a
role list:

- `metadata_public.admin` -> `UserInfo.Admin`
- `metadata_public.is_owner` -> `UserInfo.IsOwner`
- `metadata_public.avatar` -> `UserInfo.Avatar`

This appears in both:

- `extractIdentityInfo(...)` for session-based flows
- `KratosIdentityToUserInfo(...)` for admin-API identity reads

The shared `ApiTypes.UserInfo` type also reflects this model. It has:

- `Admin bool`
- `IsOwner bool`

It does not currently have a `Roles []string` field.

### 4.3 Auth responses today

`HandleAuthMeKratos` returns session and identity information with
`metadata_public.admin` and `metadata_public.is_owner`, but no role list.

Legacy/shared handlers such as `HandleAuthMe` and `users_handler.go` also rely
on the boolean `Admin` field rather than role membership.

### 4.4 User update path today

`shared/go/api/EchoFactory/echo_factory.go` updates Kratos identities through
`KratosUpdateIdentity(...)`, and today it writes admin/owner state into
`metadata_public`:

- `metadata_public.admin`
- `metadata_public.is_owner`
- `metadata_public.avatar`

This means the effective application-side authorization source of truth is
currently `metadata_public`, at least for the shared library path.

### 4.5 Separate Kratos sample backend behavior

`Kratos/backend/main.go` contains an `AdminMiddleware` that checks
`identity.MetadataAdmin["role"] == "admin"`.

This is important because it does **not** match the shared auth path, which
uses `metadata_public.admin`.

So today there are two different admin conventions in the codebase:

- shared auth convention: `metadata_public.admin == true`
- sample Kratos backend convention: `metadata_admin.role == "admin"`

They are not the same model, and no current shared authorization layer unifies
them.

## 5. Current Gaps

### 5.1 No first-class roles

The current application model cannot express:

- multiple roles per user
- page-specific access by role set
- roles beyond `admin`

### 5.2 Boolean-admin model is too narrow

`Admin bool` is a useful compatibility field, but it is not expressive enough
for the new page configuration design where access depends on membership in
named roles.

### 5.3 Inconsistent storage conventions

Admin is currently represented in two different ways:

- boolean in `metadata_public`
- string role in `metadata_admin`

This creates ambiguity about where future role checks should read from.

### 5.4 UserInfo does not carry roles

The shared `UserInfo` type does not yet expose a role list, so there is no
standard request-context representation for authorization decisions beyond
`Admin` and `IsOwner`.

## 6. Decision

### 6.1 Canonical role storage: `metadata_public.roles`

The canonical role list should be stored in Kratos identity
`metadata_public.roles` as a JSON array of strings.

Example:

```json
{
  "admin": true,
  "is_owner": false,
  "roles": ["admin", "knowledge_editor", "workspace_manager"]
}
```

This choice is recommended because:

- the shared auth path already reads and writes `metadata_public`
- current application-facing flags (`admin`, `is_owner`, `avatar`, app tokens)
  already live there
- it avoids introducing a second authorization source of truth for the shared
  app path

`metadata_admin` may still be used for Kratos-internal or privileged
administrative metadata, but it should not be the canonical application role
store for ChenWeb/shared authorization.

Backward compatibility requirement:

- the existing `metadata_public.admin` field must be preserved
- the existing `metadata_public.is_owner` field must be preserved
- adding `metadata_public.roles` must be additive and must not break existing
  projects already in production

### 6.2 Canonical authorization identity

Each Kratos-backed user should have a canonical authorization representation in
application code consisting of:

- identity id
- email
- `roles []string`
- compatibility booleans derived from roles and retained fields

At minimum:

- `admin` remains supported for backward compatibility
- `roles` becomes the primary role-membership source for new authorization
  logic

### 6.3 Canonical meaning of `admin`

During migration, `admin` should be treated as a compatibility projection of
the role model:

- if `roles` contains `admin`, the user is an admin
- the `metadata_public.admin` flag should be set accordingly for full backward
  compatibility
- existing `metadata_public.admin` may continue to be stored and read for
  legacy consumers
- the system should converge on `roles` as the source of truth and `admin` as a
  derived compatibility field

This means `admin` is conceptually just a role, but the boolean flag remains a
required compatibility projection for existing applications.

## 7. Planned Data Model Changes

### 7.1 Kratos identity metadata

Add role support in identity metadata:

- `metadata_public.roles: []string`

Recommended conventions:

- values are canonical lowercase role keys
- values are unique per user
- empty or missing means the user has no assigned roles

Example:

```json
{
  "roles": ["admin", "knowledge_editor"]
}
```

### 7.2 Shared Go user model

Extend `shared/go/api/ApiTypes/ApiTypes.go::UserInfo` with a roles field:

```go
Roles []string `json:"roles"`
```

This becomes the standard request-context role list used by shared auth,
handlers, and future authorization middleware.

Backward compatibility requirements:

- keep the existing `Admin bool` field
- keep the existing `IsOwner bool` field
- populate `Admin` from the role model in a backward-compatible way
- continue exposing `IsOwner` for legacy projects, especially `tax/`, even
  though new projects should not depend on it

### 7.3 Identity extraction

Update both:

- `extractIdentityInfo(...)`
- `KratosIdentityToUserInfo(...)`

to read:

- `metadata_public.roles`

and populate `UserInfo.Roles`.

`UserInfo.Admin` should then be derived consistently from:

- `metadata_public.roles` containing `admin`
- and `metadata_public.admin` for backward-compatible reads during migration

`UserInfo.IsOwner` should continue to be populated from
`metadata_public.is_owner` for backward compatibility.

### 7.4 Identity update path

Extend the shared user-management / identity-update path so roles can be
created and updated explicitly through Kratos identity metadata updates.

At minimum, the update path must support:

- setting the full roles array
- validating and normalizing role names
- preserving unrelated metadata fields

This should continue to use the existing GET-then-PUT merge model already used
by `KratosUpdateIdentity(...)`.

Backward-compatible write behavior:

- when roles are updated and include `admin`, set `metadata_public.admin = true`
- when roles are updated and do not include `admin`, set
  `metadata_public.admin = false`
- preserve `metadata_public.is_owner` unless it is explicitly changed by a
  legacy-compatible caller

## 8. Authorization Rules

### 8.1 Server-side authorization is authoritative

Role checks must be enforced on the server side. Frontend role data may be used
for display and navigation hints, but not as the source of truth for access
control.

### 8.2 Role membership semantics

A user has a role if and only if:

- the role appears in `metadata_public.roles`
- the role value is valid under the system's canonical role naming rules

### 8.3 Page configuration integration

This role model is intended to support `kb.page_config.access_role`.

For page-config access evaluation:

- an entry is accessible only if the entry is enabled
- and the current user has at least one role listed in
  `kb.page_config.access_role`
- if `access_role` is `null`, empty, or contains no valid roles, the entry is
  effectively suspended

### 8.4 Backward compatibility

Existing checks like:

- `if currentUser.Admin { ... }`

may continue to work during migration, but new authorization code should prefer
role-based checks.

This compatibility is not temporary-only in the narrow sense of a one-time
migration window. The shared library must continue to behave compatibly for
existing projects already in production.

## 9. Migration Plan

### 9.1 Phase 1: Add roles without breaking admin

- add `roles` to identity metadata for selected users
- add `Roles []string` to `UserInfo`
- update identity readers to populate roles
- continue to preserve and expose `Admin bool`
- continue to preserve and expose `IsOwner bool`

### 9.2 Phase 2: Dual-read compatibility

During migration:

- admin checks may read `roles` first
- if `roles` is absent, legacy `metadata_public.admin` may still be honored

This avoids breaking existing users before role backfill is complete.

### 9.3 Phase 3: Converge on one source of truth

After backfill and handler migration:

- `roles` becomes the canonical role source
- `admin` is treated as derived compatibility state
- authorization code stops depending on `metadata_admin.role`
- shared/go remains responsible for maintaining backward-compatible projections
  such as `Admin` and `IsOwner`

## 10. Open Questions

The following decisions are adopted by this spec:

- Canonical role naming should use lowercase snake_case strings.
- The initial role catalog is:
  `admin`, `root`, `guest`, `dev`, `k_engineer`, `trial`.
- `root` is reserved now but is not intended for active use yet.
- `is_owner` remains a separate backward-compatible boolean for existing
  projects such as `tax/`, but new projects, including ChenWeb, should not
  build new authorization logic around it.
- Role-management APIs and shared authorization helpers should be implemented
  in `shared/go`.

## 11. Consequences

- The system gains a scalable authorization model that fits the planned
  database-backed page configuration work.
- Kratos remains the single identity store, with application roles stored in
  identity JSON metadata.
- Existing admin-only and owner-aware behavior can continue in a fully backward
  compatible way for current production projects.
- The current mismatch between `metadata_public.admin` and
  `metadata_admin.role` becomes explicitly resolved by standardizing on
  `metadata_public.roles` for application authorization.

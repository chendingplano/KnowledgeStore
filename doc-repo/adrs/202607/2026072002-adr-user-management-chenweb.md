# ADR 2026072002 — ChenWeb User Management via Kratos with Self-Scoped Access

**Date:** 2026-07-20 \
**Status:** Implemented \
**Component:** ChenWeb `System Admin -> User Management`, shared Kratos auth, shared user model \
**Authors**: Codex

## Change Logs
* 2026/07/20, ADR created.

## Context

ChenWeb now exposes a `System Admin -> User Management` page under
`/development`. The page is backed by Ory Kratos identities, with shared auth
and identity-read/write logic implemented in `shared/go/api/auth/kratos.go` and
the ChenWeb page-specific handlers implemented in
`ChenWeb/server/api/useradminhandler/useradminhandler.go`.

The implemented feature had to satisfy several constraints discovered during
delivery:

- Kratos is the source of truth for user identities.
- there is no separate database table for user-role catalog or user-management
  entries
- operator actions often identify a user by email, not by Kratos identity id
- email values in route params may arrive URL-encoded and must still resolve
  correctly
- `admin` must remain backward compatible with the new role model introduced by
  ADR 2026072001
- Google/OIDC login can create a new Kratos user if one does not already exist
- newly created Google users usually have no `admin` or `root` role

That last point changes the access model materially: the `User Management` page
cannot be "admin only" if ordinary authenticated users are expected to view and
edit their own account details after self-registration or first-time Google
login.

## Decision

### DR1 — Kratos remains the user-management system of record

User Management in ChenWeb operates directly on Kratos identities.

- list users: Kratos Admin API
- read one user: Kratos Admin API
- update user: Kratos Admin API
- delete user: Kratos Admin API

No ChenWeb-specific mirror table is introduced for users.

### DR2 — User-targeting actions use email as the operator-facing key

Although Kratos identity id remains the canonical internal identifier, the
User Management UI and routes identify the target account by email.

Implemented route pattern:

- `PUT /api/v1/system-admin/users/by-email/:email`
- `DELETE /api/v1/system-admin/users/by-email/:email`

This was chosen because:

- the UI already displays email prominently
- operators naturally identify the target account by email
- multiple accounts with similar names are easier to distinguish by email

The backend must decode URL-escaped email values before lookup.

### DR3 — Canonical role catalog comes from project config, with hard-coded fallback

The canonical role catalog for ChenWeb User Management is loaded from:

- `ChenWeb/config.local.toml`
- `[system].access_roles`

If `config.local.toml` is absent, the key is absent, or the list resolves to
empty after normalization, the system falls back to the built-in baseline:

- `admin`
- `root`
- `guest`
- `dev`
- `k_engineer`
- `trial`

There is currently no separate `access role table`.

### DR4 — `admin` is treated as a normal role in the UI, with compatibility projection

In the UI, `admin` is selectable and removable through the same role-selection
mechanism as other roles.

Compatibility rule:

- if `admin` is present in `roles`, the admin checkbox is on
- if the admin checkbox is turned on, role `admin` is added
- if role `admin` is removed, the admin checkbox is turned off

This keeps the frontend consistent with ADR 2026072001, where `admin` is a
role but the legacy boolean flag is still preserved.

### DR5 — Access to User Management is scoped by effective role

User Management uses two effective access scopes:

#### Full management scope

Users with any of the following may manage all users:

- `Admin == true`
- `IsOwner == true`
- role `admin`
- role `root`

These users can:

- list all Kratos users
- update other users
- delete other users
- manage roles and status

#### Self-only scope

Authenticated users without `admin` or `root` effective privilege may still
open the page, but they see only their own account.

These users can:

- load the User Management page
- receive a self-scoped `/system-admin/users` response containing only their
  own Kratos identity
- edit their own basic account information

These users cannot:

- list all users
- delete any user
- change admin flag
- change explicit roles
- change account status

This behavior is required so a newly created Google/OIDC account without admin
privileges can still access and maintain its own profile.

### DR6 — Roles endpoint must not be admin-gated

`GET /api/v1/system-admin/roles` is available to any authenticated user.

Reason:

- the User Management page needs to load without a `403` in self-only mode
- the same page component is used for both full-management and self-only
  access
- role editing is still disabled in the frontend for self-only users

The endpoint exposes the role catalog, not privileged per-user data.

### DR7 — Self-only updates preserve protected authorization fields

When a self-only user edits their own account:

- `admin` remains unchanged
- `roles` remain unchanged
- `status` remains unchanged

Only safe self-service fields are updated:

- first name
- last name

This rule is enforced server-side, not only in the UI.

## Alternatives Considered

- Keep User Management fully admin-only — rejected. This breaks the
  self-registration / Google-login flow for new ordinary users.
- Introduce a separate ChenWeb user table — rejected. Kratos is already the
  system of record.
- Require Kratos identity id in the UI routes — rejected. Email is the more
  usable operator-facing key.
- Build a database-backed role catalog first — rejected for now. Project config
  already provides the required canonical role list with a safe fallback.

## Implementation

### Main backend behavior

- `ChenWeb/server/api/useradminhandler/useradminhandler.go`
  - added config-backed role catalog loading
  - added email route-param decoding and normalization
  - added fallback identity lookup by case-insensitive email scan
  - implemented full-management vs self-only access scope
  - made `/system-admin/roles` authenticated, not admin-only
  - made self-only updates preserve `admin`, `roles`, and `status`

### Shared behavior used by the page

- `shared/go/api/auth/kratos.go`
  - carries `Roles` through session-authenticated users
  - keeps `Admin` compatible with presence of role `admin`
  - supports Google/OIDC-created users in the shared session path

### Frontend behavior

- `ChenWeb/web/src/lib/services/userManagementService.ts`
  - carries `scope` and `can_manage_all` from backend
- `ChenWeb/web/src/lib/components/home3/user-management-view.svelte`
  - full-management mode for admin/root users
  - self-only mode for ordinary users
  - hides add/delete in self-only mode
  - disables status/admin/role editing in self-only mode

## Consequences

### Positive

- user identities stay centralized in Kratos
- ordinary authenticated users can maintain their own account
- Google-created non-admin users no longer hit a hard `403`
- admin/root users retain full user-management capability
- role catalog is project-configurable without requiring a database table

### Negative / accepted costs

- User Management now has two behavior modes instead of one
- frontend and backend must stay aligned on self-only restrictions
- role catalog is still config-based rather than database-based

## Verification

Verified during implementation with:

```bash
cd ChenWeb
go test ./server/api/useradminhandler ./server/api
bun run check
```

Shared auth changes used by this flow were also verified in `shared/go` with:

```bash
cd shared
go test ./go/api/auth/...
```

## References

- [2026072001 — User Roles in Kratos via `metadata_public.roles`](./2026072001-adr-user-roles-kratos.md)
- [2026072002 — Spec: User Roles in Kratos and Shared Auth](../../specs/202607/2026072002-spec-user-roles-kratos.md)
- [2026072001 — User Roles in Kratos Implementation](../../impl/202607/2026072001-impl-user-roles-kratos.md)
- `ChenWeb/server/api/useradminhandler/useradminhandler.go`
- `ChenWeb/web/src/lib/components/home3/user-management-view.svelte`
- `ChenWeb/web/src/lib/services/userManagementService.ts`
- `shared/go/api/auth/kratos.go`

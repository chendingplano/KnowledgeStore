# Per-Role Utilization Targets — Design

**Date:** 2026-04-07
**Status:** Design approved, ready for implementation
**Origin:** Team Utilization chart showed one firm-wide dashed reference line at 70%. A partner managing client relationships and a staff preparer doing heads-down tax work should not be measured against the same bar. This feature makes the target configurable per role, with role assignment managed through the existing admin users page.

## Problem

The Team Utilization chart at [/admin/time-analytics](../../web/src/routes/(admin)/admin/time-analytics/TeamUtilizationChart.svelte) renders a dashed reference line at a hardcoded 70% for everyone. Two issues:

1. **One target does not fit all roles.** Partners, managers, seniors, and staff have different billable expectations. A single global target is either too high for some or too low for others.
2. **Related firm-wide numbers are hardcoded.** `DashboardTab.svelte` has a literal `70` and a literal `"Target: 70–85%"` string. Changing the target would require a code edit in multiple places.

## Goals

- Let the admin define a custom list of roles (e.g., Partner, Senior, Staff, Admin) with a utilization target percentage per role.
- Assign roles to admin users through the existing users page.
- Team Utilization chart draws each person's dashed reference line at their role's target.
- Role name appears as a small badge under each person's name on the chart.
- Fix the related firm-wide coloring inconsistency in `DashboardTab.svelte` so all target-derived values read from a single configurable firm default.
- Existing admins without roles fall back gracefully to a firm-wide default (no migration-day friction, no blocking).

## Non-goals

- **Multiple roles per user.** One user = one role. YAGNI.
- **Role history / audit trail.** When you change someone's role, the old one is gone. No "was Senior last quarter" reporting.
- **Per-period targets.** A role's target does not change over time. If you want a different target for Q4, you edit the role.
- **Role-based permissions.** This feature is about measurement, not authorization. Role does not affect what a user can do in the app.
- **Predefined role taxonomies.** The admin defines their own list from scratch in settings. No starter set.

---

## Data model

### New table: `roles`

```sql
CREATE TABLE IF NOT EXISTS roles (
    id VARCHAR(40) NOT NULL DEFAULT gen_random_uuid()::text PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    target_utilization_rate NUMERIC(5,2) NOT NULL
        CHECK (target_utilization_rate BETWEEN 0 AND 100),
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

Notes:
- `VARCHAR(40)` with `gen_random_uuid()::text` matches the project convention set by `overhead_categories` and other tables. Cross-database compatible.
- `name` is unique **case-insensitively** via `idx_roles_name_lower` on `LOWER(name)`. Prevents "Partner" and "partner" from coexisting as separate roles. The display casing is preserved (first creator wins), but a second create with different casing returns a unique violation. Using `LOWER(name)` index instead of citext to avoid adding a new Postgres extension.
- `sort_order` controls display order in the settings list and the chart. Manual integer for now. Drag-to-reorder is a possible future enhancement.
- `NUMERIC(5,2)` holds values like `82.50`. `CHECK` constraint prevents nonsense values.

### New table: `user_role_assignments`

**Architecture note — REVISED during eng review:** The mirai project uses **Ory Kratos** for user identities (not a PostgreSQL `users` table in mirai_db). The `admin` flag lives in Kratos `metadata_public`, accessed via `auth.KratosListAllIdentities()` and `auth.KratosUpdateIdentity()`. The original design proposed adding a `role_id` column to a `users` table that does not exist in mirai_db.

The shared library defines `UserInfo` with `admin` and `is_owner` fields used across multiple projects (`tax`, `ChenWeb`, `deepdoc`). Role-based utilization targets are a **mirai-specific** concept and do not belong in the shared library.

**Solution:** a project-local junction table that maps Kratos user identity IDs to role IDs. No cross-database FK (Kratos data lives outside mirai_db). The FK to `roles` still works because both tables are in mirai_db.

```sql
CREATE TABLE IF NOT EXISTS user_role_assignments (
    user_id VARCHAR(64) NOT NULL PRIMARY KEY,
    role_id VARCHAR(40) NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_role_assignments_role
    ON user_role_assignments(role_id);
```

Notes:
- **`user_id` is the Kratos identity ID.** Stored as opaque `VARCHAR(64)` (matching Kratos's UUID-text format) with NO foreign key, since Kratos lives outside mirai_db. The mirai backend treats it as a free-form string.
- **Primary key on `user_id` enforces the "one user, one role" invariant** at the database level. You cannot accidentally create two role assignments for the same user.
- **`ON DELETE CASCADE` on `role_id`:** when a role row is deleted, all assignment rows pointing at it are automatically removed. The affected users become "unassigned" (no row in `user_role_assignments`) and fall back to the firm default target. Functionally equivalent to the original plan's `SET NULL` approach but cleaner because the assignment row simply doesn't exist rather than carrying a NULL FK.
- **The absence of a row means "no role assigned."** Pre-existing admins with no row use the firm default target. The UI enforces assignment at grant-admin time via the application flow, not via a NOT NULL column (the Kratos boundary makes DB-level enforcement impossible).
- **Index on `role_id`** speeds up `GetUnassignedAdminCount` and the cascade lookup during role deletion.

### Shared library stays untouched

The original plan proposed adding `RoleID *string` to `UserInfo` in `Shared/go/api/ApiTypes/ApiTypes.go` and `Shared/svelte/src/lib/types/CommonTypes.ts`. **This is no longer needed.** Role data is project-local to mirai. The mirai web layer joins user identities with role assignments at the handler level, not via a shared type.

Other projects (`tax`, `ChenWeb`, `deepdoc`) are unaffected by this feature.

### Separation of concerns — an invariant going forward

This feature locks in an architectural rule that future mirai work should follow:

> **Kratos stores identity and auth. The shared library stores cross-project primitives. mirai_db stores everything else.**

Concretely:
- **Kratos's `metadata_public`** is reserved for cross-project identity fields (`admin`, `is_owner`). Do not add mirai-specific fields like role, target rate, preferred client types, or anything else that's meaningful only to a CPA practice.
- **The shared library's `UserInfo`** is the minimum-common-denominator type for every consuming project. Do not pollute it with mirai concepts. If every project would benefit, it belongs there; if only mirai benefits, it belongs in mirai_db.
- **mirai_db is where mirai owns its own destiny.** Every CPA-practice concept (clients, projects, time entries, roles, utilization targets, billing configuration) lives here, often in tables keyed by the Kratos identity ID as an opaque VARCHAR.

This invariant keeps three things healthy: (1) the shared library stays thin, (2) other projects (`tax`, `ChenWeb`, `deepdoc`) never inherit mirai concepts they don't need, (3) mirai can evolve its data model freely without cross-repo coordination.

**Trade-off accepted:** some mirai operations require two-step writes (Kratos + mirai_db) and are not transactional across the boundary. The grant-admin flow is the canonical example. We accept this because the alternative is worse: atomicity-via-sharing would mean putting mirai concepts in Kratos or shared, which breaks the invariant above. At single-firm scale, partial failures are rare, visible (via the unassigned-admins banner), and self-healing (via the role dropdown).

### Modified struct: `GoalConfig`

In [table-app-settings.go:367-371](../../server/api/appdatastores/table-app-settings.go#L367-L371):

```go
type GoalConfig struct {
    TargetNetProfit                *float64 `json:"TargetNetProfit"`                 // nil = default $100K
    TargetEffectiveRate            *float64 `json:"TargetEffectiveRate"`             // nil = use firm average
    DefaultTargetUtilizationRate   *float64 `json:"DefaultTargetUtilizationRate"`    // nil = fallback to 70
}
```

**No migration needed.** `GoalConfig` is stored as a JSONB value in `app_settings`, not as table columns. Existing rows unmarshal with the new field as `nil`, and the next save writes the new field. This is the pattern the existing `TargetEffectiveRate` field already uses.

### Project-local type: admin user with role

Instead of modifying `UserInfo`, mirai defines a small project-local response type in the web layer for the "admin user enriched with role" view:

**TypeScript — `mirai/web/src/lib/api/roles.ts`:**
```typescript
import type { UserInfo } from '@chendingplano/shared';
import type { Role } from '$lib/types/go-types';

// Enriched view returned by GET /api/v1/users/admins when ?include_role=true
export interface AdminUserWithRole extends UserInfo {
  role_id?: string;
  role_name?: string;
  target_utilization_rate?: number;
}
```

The Go handler constructs this shape at the API boundary by zipping Kratos users with `GetUserRoleMap`. No shared-type changes required.

---

## Migration

**One Goose migration file**, named to match the existing convention in `mirai/project_migrations/`:

**`mirai/project_migrations/20260407000001_create_roles_and_user_role_assignments.sql`**

```sql
-- +goose Up

-- Create roles table for per-role utilization targets
CREATE TABLE IF NOT EXISTS roles (
    id VARCHAR(40) NOT NULL DEFAULT gen_random_uuid()::text PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    target_utilization_rate NUMERIC(5,2) NOT NULL
        CHECK (target_utilization_rate BETWEEN 0 AND 100),
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Case-insensitive unique index on name so "Partner" and "partner" collide.
-- Using LOWER(name) instead of citext to stay within the project's existing
-- extension set (no new Postgres extensions required).
CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_name_lower ON roles(LOWER(name));

-- User → role assignment (mirai-local; user_id is a Kratos identity ID,
-- stored as opaque VARCHAR since Kratos lives outside mirai_db).
-- PK on user_id enforces "one user, one role" at the database level.
-- VARCHAR(64) is sized for the current Kratos UUID-text format; if Kratos
-- ever changes identity ID format to something longer, this column needs
-- to grow. Documented dependency on Kratos ID format.
CREATE TABLE IF NOT EXISTS user_role_assignments (
    user_id VARCHAR(64) NOT NULL PRIMARY KEY,
    role_id VARCHAR(40) NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Fast lookup by role (for unassigned-count queries + deletion cascade)
CREATE INDEX IF NOT EXISTS idx_user_role_assignments_role
    ON user_role_assignments(role_id);

-- +goose Down

DROP INDEX IF EXISTS idx_user_role_assignments_role;
DROP TABLE IF EXISTS user_role_assignments;
DROP INDEX IF EXISTS idx_roles_name_lower;
DROP TABLE IF EXISTS roles;
```

No seed data. The admin defines their role taxonomy themselves in settings after the migration runs.

**Note on migration system:** This feature uses the Goose system (`mirai/project_migrations/`) rather than the legacy `migrations.go` Go-function approach. Goose is the forward-going convention. The existing [server/CLAUDE.md](../../server/CLAUDE.md) description of `migrations.go` as canonical should be updated in a follow-up.

---

## Backend

### New file: `mirai/server/api/appdatastores/table-roles.go`

Contains the `Role` struct and CRUD functions for the `roles` table. No schema DDL — Goose handles that.

```go
type Role struct {
    ID                    string    `json:"ID"`
    Name                  string    `json:"Name"`
    TargetUtilizationRate float64   `json:"TargetUtilizationRate"`
    SortOrder             int       `json:"SortOrder"`
    CreatedAt             time.Time `json:"CreatedAt"`
    UpdatedAt             time.Time `json:"UpdatedAt"`
    AssignedCount         int       `json:"AssignedCount"` // Computed via GetRoles
}

func GetRoles(rc ApiTypes.RequestContext) ([]Role, error)
func GetRoleByID(rc ApiTypes.RequestContext, id string) (*Role, error)
func CreateRole(rc ApiTypes.RequestContext, role *Role) error
func UpdateRole(rc ApiTypes.RequestContext, role *Role) error
func DeleteRole(rc ApiTypes.RequestContext, id string) error
```

`GetRoles` returns the full list sorted by `sort_order ASC, name ASC`, with `AssignedCount` computed via `LEFT JOIN user_role_assignments ura ON ura.role_id = roles.id GROUP BY roles.id`. One query, free information.

The same response shape is used for both the settings page (which shows the count) and the dropdowns (which ignore the count field). At this scale, returning `AssignedCount` to dropdown callers is free — not worth splitting into two endpoints. If the frontend starts noticing payload bloat (unlikely with ≤10 roles), we can revisit.

### New file: `mirai/server/api/appdatastores/table-user-role-assignments.go`

Contains the `UserRoleAssignment` struct and CRUD for the junction table.

```go
type UserRoleAssignment struct {
    UserID    string    `json:"UserID"`    // Kratos identity ID (opaque VARCHAR)
    RoleID    string    `json:"RoleID"`
    CreatedAt time.Time `json:"CreatedAt"`
    UpdatedAt time.Time `json:"UpdatedAt"`
}

// GetUserRoleMap returns a map of kratos_user_id → role_id for ALL
// assignments. Used by handlers that need to enrich Kratos users with
// their role info. Single query, O(n) to iterate the result.
//
// NOT cached — each handler call fetches fresh. At team-of-5 scale this
// is sub-millisecond. If the project grows past ~100 admin users AND
// this becomes a profiled bottleneck, introduce request-scoped caching
// via echo.Context.Set/Get. Until then, YAGNI.
func GetUserRoleMap(rc ApiTypes.RequestContext) (map[string]string, error)

// SetUserRole does an UPSERT on (user_id) keyed by primary key.
// Called by grant-admin and by the standalone "change role" endpoint.
//
// Validation is handled by the database: the FK to roles(id) will cause
// this to return a PostgreSQL FK violation error if roleID doesn't exist.
// Callers should translate that to a 400 Bad Request. Do NOT duplicate
// the existence check by doing a SELECT first — it's a race condition
// waiting to happen and adds a round trip.
func SetUserRole(rc ApiTypes.RequestContext, userID, roleID string) error

// ClearUserRole removes the assignment row for a user. No error if no row exists.
// Called by revoke-admin to clean up the role assignment side effect.
func ClearUserRole(rc ApiTypes.RequestContext, userID string) error

// GetUnassignedAdminCount returns the count of Kratos admin users who have
// NO row in user_role_assignments. Requires fetching Kratos admins first,
// then subtracting assigned user_ids. Used for the settings page banner.
func GetUnassignedAdminCount(rc ApiTypes.RequestContext) (int, error)
```

### New file: `mirai/server/api/handlers/role_handlers.go`

HTTP handlers for role CRUD:

- `GET /api/v1/roles` — list all roles with `AssignedCount`, sorted `sort_order ASC, name ASC`
- `POST /api/v1/roles` — create a new role (body: `{name, target_utilization_rate, sort_order}`)
- `PUT /api/v1/roles/:id` — update name / target / sort_order
- `DELETE /api/v1/roles/:id` — delete a role; `user_role_assignments` rows referencing it are removed by `ON DELETE CASCADE`. The response body includes the list of affected user names (for the delete confirmation dialog's named-user list), computed BEFORE the delete executes.

### New file: `mirai/server/api/handlers/user_role_handlers.go`

New handlers for role assignment, split into a separate file from the existing user_management_handlers.go to keep the boundary clean:

- `PUT /api/v1/users/:id/role` — assign or change the role of an existing admin user. Body: `{role_id: "abc-123"}`. Upsert into `user_role_assignments`. Returns 404 if the Kratos user doesn't exist, 400 if the role_id doesn't exist.

**New endpoint: `PUT /api/v1/users/:id/grant-admin`**

Two-step operation (NOT atomic across Kratos + mirai_db, see failure mode below):

1. `auth.KratosUpdateIdentity(userID, {admin: true})` — writes to Kratos
2. `appdatastores.SetUserRole(rc, userID, roleID)` — writes to mirai_db

Body: `{role_id: "abc-123"}`. Returns 400 if `role_id` is missing or does not exist. Returns 404 if the Kratos user does not exist. Returns **200 with a `status: "partial"` warning flag** if step 2 fails after step 1 succeeded (see Failure Modes below) — HTTP 500 would be misleading because admin access WAS granted.

**Modified endpoint: `PUT /api/v1/users/:id/admin`** (in `user_management_handlers.go`)

When revoking admin (`admin: false`), the handler ALSO calls `appdatastores.ClearUserRole(rc, userID)` after `KratosUpdateIdentity` succeeds. Same two-step, same partial-failure analysis.

### Modified file: `mirai/server/api/handlers/user_management_handlers.go`

**Two changes** to `HandleToggleAdmin`:

**Change 1 — block grant-via-old-endpoint (the "bypass" fix):**

At the top of the handler, after binding the request body but before calling Kratos, reject any attempt to grant admin through the old endpoint:

```go
if body.Admin {
    return e.JSON(http.StatusBadRequest, map[string]string{
        "error": "Granting admin access requires a role assignment. " +
                 "Use PUT /api/v1/users/:id/grant-admin instead.",
        "code":  "USE_GRANT_ADMIN_ENDPOINT",
    })
}
```

Why: the new `/grant-admin` endpoint enforces "admin always has a role" by requiring a role_id in the body. The old `/admin` endpoint accepts only `{admin: bool}` with no role. Without this guard, any API client (or a poorly-written internal tool) calling the old endpoint with `admin: true` creates an admin without a role, bypassing the required-role rule. After this change, the old endpoint accepts ONLY `{admin: false}` (revoke) and becomes single-purpose.

**Change 2 — clear role assignment on revoke:**

After the successful `KratosUpdateIdentity` call and before the audit log, add:

```go
// Revoking admin: clear any role assignment. A non-admin with a role
// is nonsense state. If this fails, the row lingers but is filtered
// out at read time since only admin users see role data.
if err := appdatastores.ClearUserRole(rc, userId); err != nil {
    logger.Warn("Failed to clear user role on admin revoke", "error", err)
    // Don't fail the request — Kratos already updated, role cleanup is
    // best-effort. Next read of GetUserRoleMap will still return the row,
    // but non-admin users are filtered out of the chart anyway.
}
```

The `if !body.Admin` guard from the original plan is no longer needed because the `body.Admin == true` case is rejected at the top of the handler.

### Enriched admin users fetch

The existing `HandleGetAdminUsers` handler in `user_management_handlers.go` is extended to optionally include role info:

```go
// Existing logic fetches Kratos users via shared_handlers.GetAdminUsers.
// After that, if ?include_role=true was passed:
includeRole := e.QueryParam("include_role") == "true"
if includeRole && isAdmin {
    roleMap, err := appdatastores.GetUserRoleMap(rc)
    if err != nil {
        // Log but don't fail — return users without role enrichment
        logger.Warn("Failed to fetch role map", "error", err)
    } else {
        // Fetch roles for name+target lookup
        roles, _ := appdatastores.GetRoles(rc)
        rolesByID := make(map[string]*appdatastores.Role)
        for i := range roles {
            rolesByID[roles[i].ID] = &roles[i]
        }
        // Enrich each user with role info if present in the map
        enriched := make([]map[string]any, 0, len(users))
        for _, u := range users {
            entry := map[string]any{ /* ...existing UserInfo fields... */ }
            if roleID, ok := roleMap[u.UserId]; ok {
                entry["role_id"] = roleID
                if role, exists := rolesByID[roleID]; exists {
                    entry["role_name"] = role.Name
                    entry["target_utilization_rate"] = role.TargetUtilizationRate
                }
            }
            enriched = append(enriched, entry)
        }
        // Return enriched slice
        return e.JSON(http.StatusOK, map[string]any{
            "status": "ok",
            "users":  enriched,
        })
    }
}
```

**Performance:** 2 DB queries + 1 Kratos list call per request. At team-of-5 scale this is sub-10ms. At team-of-100 scale it's still one query and still fast. No N+1 because all enrichment happens in-memory after batch fetches.

### Modified file: `mirai/server/api/router.go`

Register the new routes:
- `GET/POST /api/v1/roles`
- `PUT/DELETE /api/v1/roles/:id`
- `PUT /api/v1/users/:id/role` (change role of existing admin)
- `PUT /api/v1/users/:id/grant-admin` (atomic admin + role from dialog)
- `HandleGetAdminUsers` gains the `include_role` query param (no new route)

### Authorization

All new role management endpoints (role CRUD, role assignment, grant-admin) require **`user_info.IsOwner`** — same check used by the existing `HandleToggleAdmin`. Only the firm owner can manage roles or change who has admin access. This matches the existing mirai convention and keeps utilization targets out of reach for compromised non-owner admin accounts.

The existing `HandleGetAdminUsers` (which gains the `include_role` query param) stays at its current auth level (admin login required) since it's a read-only operation that enriches data the user was already authorized to see.

### Handler template to follow

The new `role_handlers.go` and `user_role_handlers.go` should mirror the existing [`overhead_category_handlers.go`](../../server/api/handlers/overhead_category_handlers.go) as closely as possible. That file is the established mirai precedent for CRUD-on-small-lookup-table: same `EchoFactory.NewFromEcho(...)` setup, same `rc.IsAuthenticated()` → `rc.IsOwner` gate, same error response shape (`map[string]string{"error": ...}`), same request struct binding, same HTTP status codes (200/201 on success, 400 on bad input, 403 on not-owner, 500 on server error). Copy the pattern rather than inventing a new one — consistency across handlers is more valuable than micro-optimizations in any one handler.

### Failure modes

The Kratos + mirai_db split introduces two new partial-failure scenarios. Both are visible and self-healing via the unassigned-admins banner UX already in the plan.

**Grant-admin partial failure:**
- Step 1 (Kratos) succeeds, Step 2 (SetUserRole) fails → user is admin but has no role row.
- User experience: the unassigned-admins banner count increases by 1. The next time the admin opens `/admin/settings` they see the nudge. Picking a role from the dropdown re-runs Step 2 and resolves the state.
- Response: handler returns **HTTP 200** with body `{status: "partial", role_assignment_failed: true, message: "Admin access granted, but role assignment failed. Please assign a role in Settings.", user: {...}}`. The HTTP status reflects that the user's primary action (grant admin) DID succeed. The `status` field in the body signals that the secondary effect (role assignment) failed.
- Frontend handling: the grant-admin dialog reads `status`. If `"partial"`, it shows a warning toast ("Admin access granted, but role assignment failed. Please assign a role in Settings.") and closes the dialog. If `"ok"`, it shows a success toast and closes. Either way the dialog closes because the admin transition IS complete.
- Why not HTTP 500: a 500 would imply "nothing happened, please retry." Retrying grant-admin here would re-run Kratos (already admin, harmless idempotent) and re-try SetUserRole. That's wasted work and produces confusing audit logs ("admin granted twice"). 200-with-warning is honest: the main thing worked, the secondary thing needs attention.
- **Structured error log at partial failure.** Because this is the highest-risk boundary in the feature, the handler MUST log a distinctive structured error that future monitoring can alert on:

  ```go
  logger.Error("ARX_GRANT_ADMIN_PARTIAL",
      "Admin granted in Kratos but role assignment in mirai_db failed",
      "user_id", userId,
      "role_id", roleID,
      "error", err)
  ```

  Use `logger.Error` (not `logger.Warn`) so the line stands out in log aggregation. The error code `ARX_GRANT_ADMIN_PARTIAL` is distinctive enough to grep for and to build an alert on (e.g., "page someone if this fires more than once a week"). The banner UX handles the user-visible recovery; this log line handles the operator-visible visibility.

**Revoke-admin partial failure:**
- Step 1 (Kratos) succeeds, Step 2 (ClearUserRole) fails → lingering orphan row in `user_role_assignments`.
- User experience: none. Non-admin users are filtered out before role data is read, so the lingering row is invisible.
- Risk: the next time the same person is promoted back to admin, their old role might pre-populate (if grant-admin is implemented to check for existing rows). **Mitigation:** grant-admin always UPSERT-writes a fresh row, overwriting any stale data.

**Two-phase commit is NOT worth it here.** The scope is: a single CPA firm with ~5 admins. Partial failures are rare, visible, and self-healing. Adding a transactional outbox or saga pattern would be gross overkill. This is the "boring by default" principle — embrace eventual consistency at the application layer, not the infrastructure layer.

---

## UI flow

### A. Settings page — `/admin/settings`

**New card section: "Team Roles"** (positioned directly under the existing Goal Tracker card)

**Information hierarchy** (top to bottom inside the card):

1. **Card header:** `Team Roles` (h3, `text-lg font-semibold tracking-tight`) + description line (`text-sm text-muted-foreground`): "Define target utilization rates for each role on your team."
2. **Unassigned admins banner** (when applicable — see below)
3. **Role list table** (or empty state — see below)
4. **Add Role button** positioned top-right of the card header, aligned with the title
5. **Default Utilization Target input** at the bottom of the card, visually separated by a subtle divider (`border-t border-border pt-4`)

**Rationale for including the default in Team Roles:** the default is part of the same "time targets" mental model. Goal Tracker holds money targets (Net Profit, Effective Rate). Team Roles holds time targets (per-role utilization + firm-wide default). Splitting the default across two cards would make it hidden.

**Role list table contents:**

| Column | Width | Content | Notes |
|---|---|---|---|
| Role Name | flexible, `min-w-[160px]` | `row.Name` | `text-sm font-medium` |
| Target Utilization | `w-32 text-center` | `{row.TargetUtilizationRate}%` | `tabular-nums` |
| Assigned | `w-24 text-center` | `{count} user(s)` | `tabular-nums`, muted when 0 |
| Actions | `w-20 text-right` | Edit + Delete icon buttons | `Button variant="ghost" size="icon"`, `h-4 w-4` icons |

Table headers: `text-xs uppercase tracking-wide font-medium text-muted-foreground` in `bg-muted/50`. Row hover: `hover:bg-muted/30 transition-colors duration-200` matching existing table conventions in the users page.

**Role table empty state (day one, no roles defined):**

Instead of "No roles found", show a warmth-forward empty state inside the table's body area:

- `h-12 w-12 rounded-full bg-brand-gold/10` icon container with `IconUsers text-brand-gold/70`
- `text-base font-medium`: "No roles defined yet."
- `text-sm text-muted-foreground max-w-sm mx-auto text-center`: "Create your first role to set custom utilization targets for different members of your team."
- Primary button: `[+ Add Your First Role]` (warmer copy than the default "Add Role" button in the header)

**Unassigned admins banner** (appears at the top of the Team Roles section, between the header description and the table, when `unassigned_admin_count > 0` **AND** `roles.length > 0`):

- Container: `bg-warning/10 border-l-2 border-warning rounded-r px-4 py-3 text-sm`
- Icon: `IconAlertTriangle h-4 w-4 text-warning-foreground` inline with the text
- Text: `text-warning-foreground`
- Copy: _"{N} admin user(s) don't have a role assigned. They'll use the default target until you assign them."_
- Action link on the right: `[Assign roles →]` linking to `/admin/users`, styled as `text-xs font-medium text-warning-foreground hover:underline`

**Day-one suppression rule:** the banner is hidden when zero roles are defined, even if pre-existing admins are unassigned. A warning about work the user can't do yet (assign roles before any exist) is UX-hostile. The nudge arrives only when it becomes actionable — the moment the first role is created. This prevents the day-one experience from opening on a red flag for a problem the user hasn't had a chance to create.

Self-destructs when the count hits 0 OR when roles.length hits 0. No dismiss button.

**Add Role button** (top-right of card header):

`<Button variant="secondary" size="sm">` with `IconPlus class="size-4"` + `<span>Add Role</span>` per the existing bulk action button pattern in [web/CLAUDE.md](../../web/CLAUDE.md). When the role list is empty, this button still exists but a more prominent `[+ Add Your First Role]` primary button appears in the empty state.

**Default Utilization Target input** (bottom of Team Roles card, above `border-t border-border pt-4`):

- `FormLabel`: "Default Utilization Target" (not required — has a sensible fallback)
- `Input type="number"` with `%` suffix on the right side, mirroring the `$`-prefix + `/hr`-suffix pattern from the Target Effective Rate input at [settings/+page.svelte:669-678](../../web/src/routes/(admin)/admin/settings/+page.svelte#L669-L678)
- Placeholder: `70`
- `min="0" max="100" step="1"`
- Helper text below (`text-xs text-muted-foreground mt-1`): _"Used for admin users who don't have a role assigned. Falls back to 70% if blank."_

### B. Users page — `/admin/users`

**New column: "Role"** (positioned directly after the existing Admin toggle column)

**Column spec:**
- Header text: `Role` (no qualifier — "Team Role" or "Utilization Role" is overspecified; the context is the users page)
- Width: fixed `w-[180px]`, always visible on desktop and tablet (`md:` breakpoint and up)
- On mobile (`< md`): column is hidden; role appears inside the row's details drawer (if one exists) or becomes part of the row-tap overflow menu. Never squeezed into the mobile table.
- Non-admin rows: show `—` in `text-muted-foreground text-center`
- Admin rows: show the role `<Select>` dropdown inline, full width of the cell
- Admin rows with `role_id = NULL` (pre-existing admins): show the dropdown with "Unassigned — click to set" as a placeholder in `text-warning-text`, nudging toward configuration

**Missing-role escape hatch:** the dropdown itself only contains existing roles (no "+ Create new role" option — that would require an in-place dialog flow more complex than the feature warrants). Instead, directly below the column header on the users page (or below the table, text `text-xs text-muted-foreground mt-2`): _"Need a new role? [Manage roles →]"_ where "Manage roles" is a link to `/admin/settings#team-roles`. Low-friction escape hatch without the complexity of in-place creation. Users who hit this friction during onboarding get a clear path to the right page.

- **For admin users:** a `<select>` dropdown showing all roles. No "Unassigned" option. Changing fires `PUT /api/v1/users/:id/role` and optimistically updates the row. Follows the existing optimistic update pattern at [users/+page.svelte:155-160](../../web/src/routes/(admin)/admin/users/+page.svelte#L155-L160).
- **For pre-existing admins with `role_id = NULL`:** the dropdown shows a muted "Unassigned — click to set" default, styled with `text-warning-text`. Picking a role from the list clears the warning state.
- **For non-admin users (clients):** the cell shows a muted `—`. Visually signals "not applicable."

**New flow: grant-admin dialog**

When toggling a non-admin user to admin, instead of a single-click PUT, open a new `GrantAdminDialog.svelte`:

- Title: _"Grant admin access to {name}"_
- A **required** role dropdown. No "Unassigned" option. No default selection.
- Confirm button disabled until a role is picked.
- On confirm: one API call to `PUT /api/v1/users/:id/grant-admin` with the role_id. Backend atomically sets both fields.
- Cancel / X: nothing changes. No half-state.

**Empty-state guard:** if the roles list is empty when the dialog opens (day one with no roles defined yet), the dropdown is replaced with:
> _"No roles defined yet. Create a role first in Settings → Team Roles."_

A button links directly to the settings page. Confirm button is hidden (not just disabled).

**Revoke admin flow:** unchanged from today. Single click. The backend handler clears `role_id` as a side effect — the user is never in a "non-admin with a role" state.

### C. Time Analytics chart — `/admin/time-analytics`

**Chart visual additions:**

1. **Role badge under the name.** Small muted pill using `bg-muted/60 text-muted-foreground`, positioned in a wrapper next to the name. No badge when the user has no role (the settings-page banner is the nudge, the chart does not also nag).

2. **Per-row dashed reference line.** Same visual as today (2px dashed, border-foreground, poking 4px above and below the bar), but positioned at `row.targetRate` instead of a hardcoded constant. Partners and staff will have their lines in different positions — exactly the point of the feature.

3. **Updated legend entry:** `"Target Rate"` (title case, no number). The old `"Target 70%"` label is now misleading because there is no single target.

4. **Updated tooltip:**
   ```
   Linda Estrella — Partner
   60.5h billable (91%)
   6.0h overhead (9%)
   14.0h above 60% target
   ```
   Role name appears in the header after an em-dash. Gap math reads from `row.targetRate`. If the row has no role, the header omits the em-dash suffix and the gap line appends `(default)` in muted text: _"3.0h above 70% target (default)"_.

**What does NOT change in the chart:**

- Bar width calculation stays `(billable / totalHours) * 100` and `(overhead / totalHours) * 100`. Role affects the target line and gap math, never the bar width.
- No grouping by role. Rows stay flat, ordered the way the backend returns them.

---

## Responsive & Accessibility

### Responsive behavior

Full responsive support: mobile (< 640px), tablet (640-1024px), desktop (> 1024px). Each viewport gets intentional treatment, not just "stacked."

#### Settings page — Team Roles card

| Viewport | Layout |
|---|---|
| **Desktop** | Card at natural width. Table 4 columns (Name, Target, Assigned, Actions). Add Role button top-right of header. Default target input at bottom, horizontal layout. |
| **Tablet** | Same as desktop. Card width shrinks to container. Table columns stay 4 wide with relative widths. |
| **Mobile** | Card takes full width minus page padding. Table collapses to card-list: each role becomes a stacked block showing `Name` prominent, `Target: 60%` below, `2 users assigned` below that, and Edit/Delete icons in a row at the bottom. Add Role button becomes full-width below the list. Default target input is full-width, label above input. |

#### Settings page — Unassigned admins banner

| Viewport | Layout |
|---|---|
| **Desktop, Tablet** | Banner has horizontal layout: icon + text on the left, `[Assign roles →]` link on the right. |
| **Mobile** | Banner stacks vertically: icon + text on top, `[Assign roles →]` link below as a full-width text link. Padding increases slightly for touch comfort. |

#### Users page — Role column

| Viewport | Layout |
|---|---|
| **Desktop** | Fixed `w-[180px]` Role column after Admin toggle. Dropdown inline in each admin row. |
| **Tablet** | Same as desktop. Role column width may shrink slightly, dropdown stays functional. |
| **Mobile** | **Role column hidden from the table.** Rows are tappable, opening a details sheet from the bottom showing all fields (Name, Email, Admin toggle, Role dropdown, Status). The Role dropdown appears inside the sheet with the same styling and states as desktop. No column width compression — the table stays scannable on mobile. |

#### Dialogs (RoleFormDialog, GrantAdminDialog, DeleteRoleConfirmDialog)

| Viewport | Layout |
|---|---|
| **Desktop, Tablet** | Centered modal at `sm:max-w-md` (448px) with backdrop. |
| **Mobile** | Full-screen sheet slides up from the bottom. Header sticky at top, footer sticky at bottom, body scrollable in between. Matches the shadcn-svelte Sheet pattern. Follow existing dialog component's `sm:` breakpoint behavior. |

#### Team Utilization chart

| Viewport | Layout |
|---|---|
| **Desktop, Tablet** | Chart at card width. Rows stack vertically with room for name + badge + bar + subtext. |
| **Mobile** | Chart takes full card width minus padding. Name + rate % row stays single-line. Badge wraps to the line below the name. Bar width fills the card. Subtext (60.5h billable / 6.0h overhead) wraps to two lines if needed. Tooltip becomes a tap-to-toggle popover instead of hover (since mobile has no hover state). |

### Accessibility

#### Keyboard navigation

- **Role list table (settings):** Tab cycles through Add Role button, Edit/Delete buttons on each row, Default Utilization Target input. Enter/Space activates buttons. Delete button opens the confirmation dialog; Escape closes it.
- **RoleFormDialog:** Focus enters on the name input. Tab moves name → target → Cancel → Save. Enter submits. Escape cancels.
- **GrantAdminDialog:** Focus enters on the role dropdown. Arrow keys navigate options. Enter selects. Tab moves to Confirm/Cancel. Enter submits. Escape cancels. When empty-state fallback is shown, focus enters on `[Go to Settings →]` button.
- **Users table role dropdown:** Tab enters the dropdown in each admin row. Arrow keys navigate options. Enter selects, triggers the PUT, closes the dropdown. Focus returns to the trigger.
- **Team Utilization chart:** Each bar is a `<button>` (via Tooltip.Trigger) so Tab can cycle through bars. Enter/Space opens the tooltip on mobile/keyboard. Tooltip content is announced via `role="tooltip"` and `aria-describedby` on the trigger.

#### ARIA landmarks

- Team Roles card: `<section aria-labelledby="team-roles-heading">` with `id="team-roles-heading"` on the h3.
- Role list table: `<table role="table" aria-label="Team roles and utilization targets">` with proper `<thead>` and `<tbody>`.
- Unassigned admins banner: `role="alert" aria-live="polite"` so screen readers announce it when it appears.
- Users table Role column: each dropdown gets `aria-label="Role for {user name}"`.
- Team Utilization chart: each row becomes a button with `aria-label="{Name} {Role}: {rate}% utilization, {billable}h billable, target {target}%, {gap}h {above|below} target"`. The full narrative lives in the label, not the DOM.
- The dashed target line stays `aria-hidden="true"` because it's a visual shorthand for information already in the bar's aria-label.

#### Touch targets

All interactive elements meet the 44×44px minimum from WCAG 2.5.5:

- Buttons at `size="sm"` are `h-9` (36px) — below the target. **Add padding or bump to `size="default"` (h-10, 40px)** for mobile. On desktop, 36px + visible border is acceptable per common practice.
- Edit/Delete icon buttons in the role table at `size="icon"` are 32×32. **On mobile, increase tappable area via padding to meet 44×44.**
- Select triggers at default size are 40×40 — acceptable with 2px extra padding on mobile.
- The dashed target line is not interactive, so it has no touch target requirement.

#### Color contrast

All text must meet WCAG AA (4.5:1 for normal text, 3:1 for large text):

- **"Unassigned — click to set" placeholder:** use `text-warning-foreground` instead of `text-warning-text`. Warning-foreground is the semantic token designed for readable text on the warning background; it has higher contrast in both light and dark mode.
- **Role badge secondary text:** `<Badge variant="secondary">` already uses `text-secondary-foreground` which passes contrast.
- **Target % in tooltip gap line:** `text-success-text` / `text-destructive` must be verified against the tooltip background. If the tooltip background is `bg-popover`, these should pass but warrants a visual check during implementation.
- **Muted help text (helper text below inputs):** `text-muted-foreground` passes contrast against both `bg-background` and `bg-popover`.

#### Focus indicators

All interactive elements must show a visible focus ring on keyboard navigation. Use the project's existing `focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2` pattern via the `Button` and `Select` components (already implemented there). Do not remove focus rings on new custom elements.

---

## Design system alignment

Every new UI element in this feature MUST use existing project primitives and conventions. The list below is the contract.

### Component reuse

| New element | Existing primitive |
|---|---|
| Role badge on chart | `<Badge variant="secondary" class="h-5 px-2 text-[10px] font-medium w-fit mt-0.5">` from [ui/badge](../../web/src/lib/components/ui/badge/). Matches precedent at [ChecklistSection.svelte:34](../../web/src/lib/components/documents/ChecklistSection.svelte#L34). |
| Role form dialog | `Dialog.Root` + `Dialog.Content class="gap-0 p-0 sm:max-w-md"` with `DialogHeader` and `DialogFooter` from `$lib/components/dialog`. Body wrapped in `<div class="px-6 py-5">`. Per [web/CLAUDE.md](../../web/CLAUDE.md) Standard Dialog Structure. |
| Grant admin dialog | Same dialog conventions as above. Size `sm:max-w-md`. |
| Delete role confirmation | Same dialog conventions. Size `sm:max-w-md`. Footer Delete button uses `variant="destructive"`. |
| Form field labels | `<FormLabel required>` for required fields per [web/CLAUDE.md](../../web/CLAUDE.md) Form Field Guidelines. |
| Number input with suffix | Mirror the existing Target Effective Rate input pattern at [settings/+page.svelte:666-678](../../web/src/routes/(admin)/admin/settings/+page.svelte#L666-L678). Suffix is `%` in a positioned span. |
| Loading spinner in buttons | `<Spinner size="xs" variant="current" />` inline before button label. |
| Table row animations | `in:fly|global={{ duration: 350, y: 8, easing: cubicOut }}` and `animate:flip` matching [DetailsTab.svelte:114-115](../../web/src/routes/(admin)/admin/time-analytics/DetailsTab.svelte#L114-L115). |
| Table skeleton | `<TableSkeleton rows={4} columns={4} columnWidths={[40, 20, 20, 20]} />` matching [DetailsTab.svelte:76](../../web/src/routes/(admin)/admin/time-analytics/DetailsTab.svelte#L76). |
| Action buttons in table header | `<Button variant="secondary" size="sm">` with `<IconX class="size-4" />` + `<span>Label</span>` per [web/CLAUDE.md](../../web/CLAUDE.md) Bulk Action Buttons. |
| Icons | `@tabler/icons-svelte/icons/<name>` only. No `@iconify/svelte`. Specific icons: `IconPlus`, `IconUsers`, `IconAlertTriangle`, `IconEdit`, `IconTrash`. |
| Toasts | Existing `toast.success()` / `toast.error()` pattern via `svelte-sonner`. |

### Svelte 5 conventions

All new components follow the project's Svelte 5 rules in [web/CLAUDE.md](../../web/CLAUDE.md):

- Event handlers: `onclick={...}`, never `on:click={...}`
- Page state: `import { page } from '$app/state'` (not deprecated `$app/stores`)
- Runes: `$state`, `$derived`, `$effect` — not stores where runes suffice
- New files are PascalCase Svelte components (`GrantAdminDialog.svelte`, `RoleFormDialog.svelte`)

### Semantic tokens

All colors use semantic tokens. No hardcoded Tailwind color utilities for theme-aware elements:

| Use case | Token |
|---|---|
| Warning banner background | `bg-warning/10` |
| Warning banner border accent | `border-warning` |
| Warning text | `text-warning-foreground` |
| Warning nudge text (dropdown placeholder) | `text-warning-text` |
| Destructive action | `variant="destructive"` |
| Success (gap above target) | `text-success-text` |
| Destructive (gap below target) | `text-destructive` |
| Muted dash, disabled states | `text-muted-foreground` |
| Card header bg | `bg-muted/50` |
| Row hover | `hover:bg-muted/30` |

The chart's bar colors (`bg-emerald-500` and `bg-muted-foreground/30`) stay as-is. These were hardcoded in the existing chart before this feature and should not be changed in this PR. A follow-up could move them to semantic tokens.

### DESIGN.md gap

The project has no DESIGN.md. This feature operates against the scattered conventions in [web/CLAUDE.md](../../web/CLAUDE.md) and existing component precedents. **Follow-up recommended:** run `/design-consultation` to establish a DESIGN.md as the single source of truth. This would calibrate ALL future design work, not just this feature.

---

## Design decisions flagged during review (intentional, not accidental)

Two patterns in this plan could superficially look like generic AI-slop treatments. They are kept on purpose for the reasons below. If a future review flags them, this note is the trail.

### Empty-state icon in a colored circle

The Team Roles empty state uses `h-12 w-12 rounded-full bg-brand-gold/10` with a Tabler icon inside. On its own, this is the "icon in colored circle" pattern that signals generic SaaS templates. It is kept here because:

1. **Precedent:** the same treatment already exists at [OtherDocumentsSection.svelte:162](../../web/src/lib/components/documents/OtherDocumentsSection.svelte#L162) for empty states in the documents UI. Consistency across the app beats avoiding a generic pattern in one place.
2. **Empty states need a visual anchor.** A card that otherwise holds a dense table collapsing to pure typography on the empty state creates a jarring transition. The icon gives the eye something to land on.
3. **Brand-gold at 10% opacity** is an accent, not a dominant color. The warmth is the point.

### Unassigned-admins banner with colored left border

The banner uses `bg-warning/10 border-l-2 border-warning`. The AI slop blacklist calls out colored left borders as pattern #8, but specifically for *decorative* borders on content cards ("look, colorful"). This banner is different:

1. **Semantic, not decorative.** The left border is the shape of a warning/info banner in established design systems (GitHub, Linear, Stripe, Radix). The convention is so universal it reads as "pay attention" without needing an explicit icon.
2. **Not on a card.** The banner is inside a card, acting as inline guidance. It's not a card styling choice.
3. **Two pixels wide, not three.** Restraint. Enough to anchor the warning color, not enough to feel shouty.

---

## User Journey — Day One

Storyboard the full first-time-user experience, from "this PR just merged" to "I'm using the feature." Every friction point here is a friction point that real users will feel.

| # | User does | User feels | What supports the feeling |
|---|---|---|---|
| 1 | Merges PR, Goose migration runs automatically on server restart | Competent | Automatic migration, no manual SQL |
| 2 | Opens `/admin/settings`, scrolls to the new Team Roles card | Curious | Clear section header + description |
| 3 | Sees empty roles table with warmth empty state (no red warning banner) | Invited, not nagged | **Day-one banner suppression:** banner only shows after first role exists |
| 4 | Clicks the primary `[+ Add Your First Role]` button | Decisive | Warmer CTA copy than the header's default "Add Role" |
| 5 | RoleFormDialog opens, types "Partner", tabs to target, types 60, submits | Focused | Minimal form, sensible autofocus on the name field, tab order matches reading order |
| 6 | Row flies in with animation, toast confirms | Accomplished | `in:fly` animation matches existing admin tables, toast is confirmation not celebration |
| 7 | Sees unassigned admins banner appear for the first time (now that she has a role) | Appropriately informed | Banner text: "2 admin users don't have a role assigned." with `[Assign roles →]` link |
| 8 | Clicks the assign-roles link, lands on `/admin/users` | Goal-directed | Same-tab navigation, page loads with existing users table |
| 9 | Sees the new Role column, her row shows "Unassigned — click to set" in warning-text | Slightly guilty, but nudged | Warning color signals "hey, you" without being a blocker |
| 10 | Clicks the dropdown on her own row, selects "Partner" | Resolved | Optimistic update, row updates instantly, no toast (low-friction actions don't need celebration) |
| 11 | Sees Linda Ding's row is also "Unassigned", but Staff role doesn't exist yet | Slight annoyance: "Now I have to go back to settings?" | **Escape hatch:** below the table, "Need a new role? [Manage roles →]" — not in-line, but visible |
| 12 | Returns to settings, creates Staff role, returns to users page | Mild context-switch fatigue (acceptable for a one-time onboarding action) | — |
| 13 | Assigns Linda Ding "Staff", banner count drops to 0, banner disappears | Completion | Self-destructing banner, no d... (46 KB left)
# User Management — create Kratos accounts

**Date:** 2026-10-27 \
**Scope:** Adding users from Development → System Admin → Users and Accesses → User Management.  
**Code root:** `ChenWeb/server/api/useradminhandler/create.go`

## Summary

Add User opens an account form instead of displaying a placeholder error. Administrators can provide an email, initial password, name, status and roles. Successful creation immediately adds the account to the visible list. The form supports English and Chinese.

The email is marked verified by the existing Kratos provisioning helper. No verification or invitation email is sent; the administrator must provide the initial credentials to the user.

## Details

`POST /api/v1/system-admin/users` accepts `email`, `password`, `first_name`, `last_name`, `status`, `admin` and `roles`. Authentication and the existing `canManageAllUsers` policy are required: administrator, owner, admin role or root role. Other authenticated users receive 403; unauthenticated users receive 401.

Email is trimmed, lowercased and validated. Password must be nonempty, with strength requirements enforced by Kratos. Status accepts active (default), inactive or trial. Trial accounts have active Kratos state and the trial role. Role normalization follows the existing editor.

The endpoint uses `auth.KratosCreateIdentityWithPassword`, then `auth.KratosUpdateIdentity` to set roles and state, using `KRATOS_ADMIN_URL`. Success returns HTTP 201 with `{status: "ok", user: ...}`. Invalid input returns 400, duplicate email returns 409, and other provider failures return 502. Passwords are excluded from the response. The form clears its password after success or closing.

If configuration fails after creation, the endpoint attempts to delete the new identity. Failed cleanup is logged with the identity ID and the response tells the operator to refresh and edit the account. Creation is logged with the acting administrator ID.

Tests in `create_test.go` cover authorization, input validation, creation credentials, trial roles, duplicate emails and rollback. Verify with `go test ./server/api/useradminhandler`, `mise build-server`, and `cd web && bun run check`.

## Known limitations

- Provisioning and role assignment are separate Kratos operations; cleanup after a configuration failure is best effort.
- Phone credentials are not provisioned by this form.
- The initial password is not automatically expired or emailed.

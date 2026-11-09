# Object type registry and human review

**Date:** 2026-11-08

**Scope:** Accepting newly discovered object types without interrupting document extraction, reviewing them, and diagnosing model response failures.

**Code root:** `ChenWeb/server/api/doc-processing`, `ChenWeb/web/src/lib/components/home3`, `shared/go/api/llm`

## Summary

Document processors can discover a new kind of object without failing an entire chunk. Existing object types start approved; unfamiliar names are saved as proposed types for human review. Administrators review them at **System Admin → Database Maintenance → Object Types**, inspect their original wording and available source information, and approve suitable entries. Approval retains the same entry and references.

The provision processor still validates response structure, required evidence, roles, and provision codes. Only object type names are open to discovery. Failed model attempts now log the complete response and identifying context so an operator can see exactly what violated the response contract.

## Details

### Registry and discovery

`ChenWeb/project_migrations/20261108000301_object_type_registry.sql` creates `kb.object_types`. The ten established broad names (`equipment`, `material`, `system`, `process`, `organization`, `person`, `place`, `document`, `concept`, `other`) are approved. Existing nonstandard names are backfilled as proposed, preserving their original wording. Legacy compact codes (`eq`, `mat`, etc.) resolve to the established names rather than creating proposals.

Names are normalized using the same trim, lowercase, whitespace/punctuation and underscore conventions as artifact objects. The registry has a unique canonical name and an optional unique `legacy_code`. Proposal insertion is atomic and never overwrites an existing approval or the first observation. Go's `ObjectTypeSQLStore.Resolve` also resolves table-managed legacy codes. Database triggers on `kb.artifact_objects` and `kb.object_nodes` cover other producers and direct object writes, canonicalize stored type strings, and retain their original spelling in `ext_info.object_type_raw`.

Provisions register types after successful response validation and before reconciliation. Their first observation includes record/run, processor, model, prompt and source spans. Other object writers preserve the available record, artifact kind and spans; historical rows and manual object nodes may have less provenance. Registry entries record first observation, not a complete occurrence history. Rediscovery does not replace it.

Compact provision response `o[].t` accepts a nonblank string. The old code map is only a wire compatibility adapter, not an acceptance list. Prompt v8 explains that new broad type names may be returned. Its generated embedded fallback is refreshed with the prompt source. Unknown types remain usable while proposed; they do not become `other` or disappear.

### Review and approval

- `GET /api/v1/kb/object-types` lists entries and provenance.
- `POST /api/v1/kb/object-types/:id/approve` approves an existing entry using the authenticated user's ID.
- Both require admin/owner access or an `admin`/`root` role; hiding a menu is not the authorization boundary.
- Repeated approval preserves the first reviewer and approval timestamp. Invalid IDs return 400, missing entries 404, and storage failures a logged 500.

The English/Chinese page supports proposed/approved/all filters, search, provenance detail, and approval. Per-tab session storage restores filters, selection and scroll after menu navigation. New types can remain proposed while awaiting judgment; no rejection/deletion/merge operation is included.

### Object matching

SQL candidate retrieval prioritizes same-type names only for approved types. Deterministic `exact_name` scoring requires approved type compatibility; proposed types receive no type-based confidence boost and are never treated as a wildcard. Approval is read directly from the registry, so it affects subsequent matching without a worker restart. It does not automatically rerun previous reconciliation. Independent name evidence and the existing ambiguous-object LLM remain usable; the LLM can still see the supplied type text as context.

### Diagnostics

`shared/go/api/llm/structured_output.go` logs every failed parse, schema validation and provider attempt with record/run IDs, provider/model/profile, prompt, contract name/schema hash, attempt limit, stage, error and full raw response. Provision chunk calls also supply zero-based chunk index, chunk count and source line range. The persisted provision processor log's `extra_info.structured_output_failures` retains raw errors from both primary and fallback branches; both errors are wrapped so neither becomes inaccessible to error inspection. Credentials and arbitrary caller metadata are not logged by the new diagnostics.

### Deployment and verification

The project startup migration runner loads the SQL migration before serving requests. Deploy the migration, API/worker binaries, frontend and prompt files together. Deploy the shared LLM changes with the application binaries; no shared schema migration is required. This implementation was verified locally and does not itself deploy to production or retry input 224. The production fallback account's quota remains an independent operational issue.

An opt-in PostgreSQL regression (`TestObjectTypesPostgresMigration`) refuses a database with an existing `kb` schema. It tests Up/Down/Up, seed/backfill, aliases, source preservation, type edits, approval idempotence, and concurrent discovery. Focused Go/API/client tests and mocked browser interactions cover extraction and human review. The broader baseline has unrelated failing Go and WPI frontend checks, documented in the implementation plan.

## Known limitations

- Review supports approval; synonym merging, rejection and retirement are separate work.
- Older failure logs cannot gain missing response fields retroactively.
- Migration Down removes the registry/triggers but retains canonicalized object names and preserved raw provenance. Reapplying seeds established types and reproposes nonstandard types; review decisions are not retained across dropping the registry.

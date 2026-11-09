# kb.object_types

Authoritative registry for broad object types across document processors. Defined by `ChenWeb/project_migrations/20261108000301_object_type_registry.sql`.

| Column | Purpose |
| --- | --- |
| `id` | Stable BIGSERIAL primary key |
| `name` | Unique, nonblank normalized canonical name |
| `legacy_code` | Optional unique compact alias, e.g. `eq` |
| `status` | `approved` or `proposed`; default `proposed` |
| `raw_value` | Original spelling from first discovery |
| `source_record_id`, `source_run_id` | First known source; 0 when unavailable |
| `source_processor`, `source_model`, `source_prompt` | First known processing context |
| `source_spans` | JSONB array of first known source-line spans |
| `created_at` | TIMESTAMPTZ discovery time |
| `approved_at`, `approved_by` | First human approval time/user; seeds use `migration` |

Ten established types are seeded approved. Unknown names are inserted proposed; concurrent discovery converges on one row and does not downgrade approval. Database triggers on artifact objects and canonical object nodes maintain registration and preserve `ext_info.object_type_raw`. Proposed names are saved and displayed but do not receive deterministic type-based candidate priority or matching confidence.

See [Object type registry and human review](../doc-repo/devdocs/202611/2026110804-devdoc-object-type-registry.md).

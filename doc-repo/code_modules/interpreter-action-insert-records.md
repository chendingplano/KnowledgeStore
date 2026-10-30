# Action Interpreter — insert records

**Date:** 2026-10-30 \
**Action class ID:** `insert-records` \
**Status:** proposed design; this action class is not implemented or registered. The batch, transaction and result rules below are proposed defaults. \
**Scope:** insert one or more records into one database table in one execution. \
**Related design:** [Action Interpreter](interpreter-action.md) and [WPI actions](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#actions)

## 1. Operation

`insert-records` inserts an ordered array of records into one table. Each input record
produces one new row. One record is represented by an array containing one object.

The action performs inserts only. It does not update existing rows, perform upserts,
skip conflicting records or create tables. A uniqueness conflict fails the execution.
The existing `save` action already supports inserting one page input document; this
proposed action gives insertion its own class and supports several records explicitly.

All rows belong to one transaction on one database connection. Either every row commits,
or none does. The action's responsibility is one batch insertion, even if the implementation
uses several SQL statements.

## 2. Class and instance attributes

The class descriptor lists every supported attribute and its type, default and required
rule. The action class ID names the server code that implements it; following the current
action model, it has no `code_module_id`.

### Class attributes

| Attribute | Type | Meaning |
| --- | --- | --- |
| `descriptor_id` | string | `insert-records`; identifies the class within `kb.wpi_descriptors` rows of kind `action`. |
| `schema_version` | string | The supported descriptor format, to be assigned when this design is implemented. It is not the class revision. |
| `description` | text, optionally localized | Describes the operation for authors. |

The saved action definition includes a complete copy of the class in `class` and names
it in `action`. An instance cannot change the class attributes or the embedded class copy.
Source class changes affect only actions placed afterwards. Source revision provenance,
runtime instance identity and execution identity follow [Action Interpreter](interpreter-action.md).

### Instance attributes

| Attribute | Type | Required/default | Meaning |
| --- | --- | --- | --- |
| `table` | string | Required | Destination table. Uses the existing WPI table naming and configured database resolution rules. |
| `records` | array of JSON objects, or a supported reference resolving to that array | Required | Records to insert, in order. A missing value, `null`, an object alone or a non-object array member is an error. |
| `fields` | array of field mappings | Required, nonempty | Maps input record attributes to writable destination columns and defines validation rules. |
| `returning` | array of column mappings | Default `[]` | Columns to return for each inserted row, such as a generated ID. |
| `args` | JSON object | Default `{}` | Invocation arguments, with the existing WPI argument scope and substitution rules. |

`records` may be a literal array or a whole-value reference such as `$input_doc.records`
or `$args.records`. Resolving the reference preserves its JSON type; the interpreter
must not stringify an array or treat its contents as expressions. Whole-array resolution
is a requirement of this proposed action, not a claim about the current resolver.

The runtime resolves references for each execution without changing the saved definition.
Request arguments and input data may supply values; they cannot replace the stored table,
column mappings or action body.

### Field mappings

| Attribute | Type | Required/default | Meaning |
| --- | --- | --- | --- |
| `attribute` | string | Required | A top-level attribute of each input record. |
| `column` | string | Required | The destination column name. |
| `required` | boolean | Default `false` | When true, the input attribute must be present and non-null. |
| `rules` | validation object | Default `{}` | Existing WPI save validation rules: `max_length`, `pattern` and `format`, with the same supported values and semantics as `save`. |

Duplicate destination columns or duplicate input attributes in `fields` are invalid.
Only mapped attributes are written; additional input attributes are ignored. Mappings
address literal top-level keys, not expressions or nested paths.

A missing optional attribute omits its column for that row, allowing the database default
to apply. An explicit JSON `null` supplies SQL `NULL` and does not request a default.
Database constraints still apply in both cases. An empty string is a supplied value;
additional validation rules determine whether it is acceptable.

Generated columns must not be mapped for insertion. Normally a generated ID is omitted
from `fields` and requested through `returning`. If a record omits every mapped column,
the action inserts a default-values row, subject to the table's constraints.

### Returned column mappings

Each entry of `returning` has a `column` naming a readable destination column and an
`attribute` naming a top-level key in the returned object. Both are required strings;
duplicate output attributes are invalid. Without `returning`, the action returns a count
and an empty returned-record array, rather than all columns implicitly.

## 3. Saved action example

This example inserts the records in the page input document's `new_customers` array.
The complete `class` copy is omitted here for readability; the saved page must contain it.
The example is the proposed descriptor shape, not a descriptor accepted by today's code.

```json
{
  "action": "insert-records",
  "table": "public.customers",
  "records": "$input_doc.new_customers",
  "fields": [
    {
      "attribute": "name",
      "column": "user_name",
      "required": true,
      "rules": { "max_length": 64 }
    },
    {
      "attribute": "email",
      "column": "email",
      "required": true,
      "rules": { "format": "email" }
    },
    {
      "attribute": "phone",
      "column": "phone_number"
    }
  ],
  "returning": [
    { "column": "id", "attribute": "id" }
  ]
}
```

An input document for that action:

```json
{
  "new_customers": [
    { "name": "Alice", "email": "alice@example.com" },
    { "name": "Bo", "email": "bo@example.com", "phone": null }
  ]
}
```

Alice's phone column uses the database default. Bo's phone column receives SQL `NULL`.
The action does not mutate `new_customers` or write generated IDs into the page input
document automatically.

## 4. Execution

1. Locate the saved action in its stored page using the page descriptor ID and JSON Pointer.
   Require an authenticated caller and apply the applicable page and database access checks.
2. Validate the action against its embedded class copy. Resolve its invocation arguments
   and `records` value without modifying either saved configuration or caller input.
3. Resolve the destination through the configured shared connection pools. Verify the
   table and columns in that database's catalog, including their suitability for insertion
   and returning. Quote SQL identifiers and bind every record value as a parameter.
4. Validate all records before beginning writes. Report validation errors with zero-based
   record indexes and input attribute names. Enforce the server's request and batch limits
   before writing; an oversized batch fails rather than being split into separate commits.
5. Begin one transaction, insert all records and collect requested return values. Preserve
   the association between each input record and its returned object; do not assume a
   database's unordered bulk result happens to match input order.
6. Commit the transaction. Report success only after commit succeeds. Roll back if an
   insertion fails. Do not return provisional row results as a successful partial batch.

An empty `records` array is a valid no-op after descriptor, access and target validation.
It returns `inserted_count: 0` and `records: []` without starting an insertion transaction.
The transaction guarantee covers inserted rows; generated sequence values can still be
consumed by a rolled-back attempt.

## 5. Result and errors

A successful execution returns the inserted count and the requested values:

```json
{
  "inserted_count": 2,
  "records": [
    { "id": 101 },
    { "id": 102 }
  ]
}
```

When `returning` is nonempty, `records` contains one object per input record in input
order. When it is empty, `records` is `[]`, regardless of the inserted count. These are
the action's result fields; any transport envelope follows the WPI API conventions.

| Failure | Behavior |
| --- | --- |
| Invalid descriptor, target or input shape | Reject before inserting. |
| Record validation failure | Reject the batch and identify the affected record indexes and attributes. |
| Permission failure | Reject before inserting; return an access error. |
| Database constraint failure | Roll back the batch and report a safe error. Include a record index only when the failing record is known reliably. |
| Failure with confirmed rollback | Report failure; no inserted rows remain from this execution. |
| Connection loss or timeout with uncertain commit outcome | Report that the outcome is unknown; do not claim that rollback succeeded or that no rows were inserted. |

Repeated executions attempt new inserts. Action instance IDs and execution IDs do not
provide deduplication. The interpreter must not automatically retry an insertion after
an uncertain outcome. A caller should reconcile the result before retrying; uniqueness
constraints can prevent duplicate business keys but do not provide a general retry protocol.

## 6. Storage, identity and logging

The class is stored in `kb.wpi_descriptors` with `kind = 'action'` and
`descriptor_id = 'insert-records'`. Saved uses live inside their page descriptors in
`kb.frontend_pages`; they have no independent database rows.

The interpreter assigns a unique runtime action instance ID and a new execution ID for
each invocation. Neither ID is serialized into the page descriptor. The same runtime
instance may execute repeatedly with different input records.

Log the execution ID, runtime instance ID, stored page reference, target, requested count,
committed count when known, duration and outcome. The backend uses the shared logger
conventions. Do not log record contents or raw database errors containing submitted values.

## 7. Implementation and documentation work

This document defines a proposed action, not a registered code module or an implemented
API. Implementing it requires class registration, descriptor validation, typed reference
resolution, transactional execution, result handling and logging. Shared database pools
must be used; the action does not open an independent connection pool.

The [overall WPI design](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#actions)
does not yet list `insert-records`. The ChenWeb `wpi-data-actions` specification and
descriptor/runtime contracts also need corresponding updates when this proposal is
implemented. Implementation verification should cover batch rollback, missing versus null
values, generated values and ordering, empty input, access rejection and uncertain commit
handling. This document does not change those specifications or add tests.

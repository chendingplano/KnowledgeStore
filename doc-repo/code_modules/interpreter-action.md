# Action Interpreter — defining and running actions

**Date:** 2026-10-30 \
**Status:** guiding design. Complete class copies and separate runtime action instance IDs are the intended model, not a claim about the current implementation. \
**Scope:** action classes, saved action definitions, runtime instances, execution identity and storage. \
**Code roots:** `ChenWeb/web/src/lib/wpi/`, `ChenWeb/server/api/wpi/`

## 1. What an action does

An action performs one defined operation, such as querying a table, running a stored SQL
statement, reading a registered file, saving data or opening a page. The action descriptor
says what operation to perform and supplies its configuration; the interpreter's code
implements the operation.

“One operation” describes a responsibility. It does not promise a single SQL statement or
an atomic transaction. Any transaction guarantee belongs to the contract of the particular
action class.

The overall design is [Web Page Interpreter](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md),
especially [Descriptors and instances](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#descriptors-and-instances)
and [Actions](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#actions).

## 2. Classes, saved definitions and runtime instances

The model distinguishes three stages:

| Stage | Meaning |
| --- | --- |
| Action class | A reusable descriptor defining one kind of action and all of its attributes. |
| Saved action definition | One use of the class, embedded where it is used in a page descriptor, containing a complete class copy and the use's instance attribute values. |
| Runtime action instance | One running copy of that saved definition, created by the interpreter within a particular page instance and assigned a unique instance ID. |

The WPI devdoc calls an embedded use an *action instance*. This document uses *saved action
definition* when distinguishing its persisted configuration from the runtime object.

When an action is placed in a page, the authoring system copies its complete class
descriptor, including defaults and attribute definitions, into the action's `class` field.
The action names its source class in `action` and sets its instance attribute values
beside the copy. The copy is made when the action is placed, before the page is run.

Afterwards, changes to the source class affect only new copies. Loading or executing an
existing page must use its embedded copy rather than silently reloading the latest class
defaults. Copying includes nested objects and arrays, so changing one instance cannot
alter another instance or its source class.

When the interpreter opens a page, it creates runtime instances from the saved definitions
and assigns their instance IDs. Opening the same page as another page instance creates
another set of action instances with new IDs. Showing an existing page again from the
Panel Cache retains that page's action instances and their IDs.

## 3. Attributes and implementation

The class descriptor enumerates every supported attribute and defines its type, whether
it is a class or instance attribute, and its default or required-value rule where applicable.
Validation uses this contract before an action runs.

| Kind | Rule |
| --- | --- |
| Class attribute | Copied from the class and immutable to the instance. |
| Instance attribute | May be set by the saved action definition or changed on its runtime instance within the class's declared rules. |

The existing action class model has `descriptor_id`, `schema_version` and `description`
as class attributes. An action class ID names the code that implements it; action classes
currently have no `code_module_id`. The class's code defines its supported instance
attributes, and the stored class supplies defaults or marks required values.

An instance may set only declared instance attributes. It cannot override class attributes
or modify the copied class descriptor. These rules apply when authoring, validating and
executing the action.

Runtime argument resolution is separate from editing configuration. For example, resolving
`$args.id` to `7` for one invocation must not replace the saved expression with `7` or
affect a later invocation. Runtime changes are not automatically persisted into the page
descriptor.

## 4. Identity and lifetime

Action class descriptors are identified by `kb.wpi_descriptors.descriptor_id`, within rows
whose `kind` is `action`. The table stores versions, so a particular class revision is
identified by its kind, descriptor ID and version. `schema_version` identifies the descriptor
format; it is not the source class revision.

The embedded class copy should retain the source revision if exact provenance is needed.
That provenance does not create a live link to the current class.

| Identity | Lifetime and purpose | Saved in the page descriptor? |
| --- | --- | --- |
| Class descriptor ID | Identifies the source action class, such as `load` or `open-page`. | Yes, in `action` and the copied class. |
| Action instance ID | Identifies one runtime action within one page instance. | No. |
| Execution ID | Identifies one invocation of an action, including its log entries. | No. |

A button's action may run several times while its page stays open. Those invocations use
the same action instance ID and different execution IDs. Another open copy of the page
has a different action instance ID for its copy of that action.

The interpreter generates runtime IDs with uniqueness across concurrently existing
instances. Runtime instance IDs and execution IDs must never be serialized into page
descriptors or reused by loading or copying a page. Execution IDs may appear in logs;
the prohibition concerns saving runtime identities as part of the page definition.

## 5. Where actions are stored

Action classes have rows in `kb.wpi_descriptors`. Saved action definitions are embedded
where they are used in WPI page descriptors, for example:

- an element's event handler, such as `on_click` or `on_row_click`;
- a list's `source`;
- a page's `input` or `save_action`;
- another action's attributes, such as an `open-page` action's `input`.

Action definitions have no independent database rows. Pages themselves are stored in
`kb.frontend_pages`, so their embedded actions are persisted as part of those pages.

Saving, exporting or copying a page serializes the action configuration and its embedded
class copy. It omits runtime objects, resolved invocation arguments, instance IDs and
execution IDs.

## 6. Execution and server authority

An execution uses the runtime instance's configuration, resolves the arguments for that
invocation and performs the class's defined operation. Each invocation gets its own
execution ID for logging and diagnosis.

The existing backend executes server actions by locating their definitions in stored pages,
using the page descriptor ID and the action's JSON Pointer. A runtime instance ID does not
replace this stored reference or authorize an operation. The browser cannot supply an
arbitrary action body, SQL statement, table name or file path to change the stored action's
operation.

The existing restrictions remain part of the action contracts: `query` executes a stored,
read-only statement from `kb.stored_stmts`, and `load-file` reads registered JSON content
from `kb.stored_files`. Validation and access checks belong on the server for server-side
operations.

## 7. Relationship to the current implementation

The current implementation loads action classes and merges their defaults with the
attributes embedded in stored pages. The guiding design replaces that live merge with
validation and execution against the complete class copy saved in each action definition.
The existing devdoc describes an execution ID for each action run; this document also
distinguishes a runtime action instance ID that lasts for the owning page instance.

This document records the intended model. It does not change the interpreter, descriptor
format or OpenSpec contracts. Implementing it requires corresponding updates to the
applicable specifications and code, including descriptor serialization, validation, runtime
identity and backend action execution. The existing overall devdoc and specifications
have not yet been revised to include all of these distinctions.

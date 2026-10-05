# Decision Policy Store — versioned task instructions for decision models

**Date:** 2026-10-05 \
**Scope:** What a decision policy is, how apps store and version policies, and how to use one in a decision request. Open this when you need task-specific instructions (such as a definition of prompt injection) for a decision model.
**Code root:** `shared/go/api/decisionpolicy`

**Traceability — openspec:**

- `shared/openspec/changes/archive/2026-10-05-add-decision-policy-store/proposal.md`: why this exists.
- `shared/openspec/changes/archive/2026-10-05-add-decision-policy-store/design.md`: table layout, API, rationale, alternatives considered, risks and trade-offs.
- `shared/openspec/changes/archive/2026-10-05-add-decision-policy-store/tasks.md`: implementation log.
- `shared/openspec/specs/decision-policy-store/spec.md`: the requirements in force. **If behavior changes, update this spec file, not just this doc.** This doc explains the feature for people and points at the code; the spec is the contract.

## Summary

A decision model answers short, typed questions about some material, called the *state* (see [2026100502-devdoc-jev-emulated-decision-model](2026100502-devdoc-jev-emulated-decision-model.md)). Many tasks need written instructions before the questions make sense. For example, "Is this message a prompt injection?" needs a definition of prompt injection, a list of the tricks to look for, and how cautious to be. We call that text a **policy**.

The policy goes into the state, next to the material being judged, so every question in a request sees it. Because it sits at the start of every prompt, the model provider can also reuse (cache) it instead of re-reading it for each question.

How a policy is worded strongly affects how accurate the answers are, so policies get rewritten and tested over time. This store keeps every policy in the database with a full history:

- Each change to a policy's text is saved as a new numbered **version**. Old versions are never changed or lost.
- One version is the **current** one, which apps use by default. A new wording can be saved without making it current, so it can be tested first. The current version can also be moved back to an older one if a new wording turns out worse.
- Deleting a policy hides it from normal use but keeps its history, so a past decision can always be traced to the exact text it used.

## Where things live

- **Code:** `shared/go/api/decisionpolicy/`. `store.go` holds the operations, `types.go` the data types and errors. Tests are in `store_test.go` (no database needed) and `integration_test.go` (real Postgres; runs only when `DECISIONPOLICY_TEST_DSN` is set).
- **Database:** two tables in the Postgres `shared` schema. `shared.decision_policies` holds one row per policy: name, description, current version and status. `shared.decision_policy_versions` holds one row per version, with the policy text.
- **Migration:** `ChenWeb/shared_migrations/20261005000001_create_shared_decision_policies.sql`. ChenWeb applies it automatically at server start. Any other app that wants the store must copy this file into its own `shared_migrations/` directory.
- **No user interface or HTTP endpoints yet.** Apps call the Go API directly. An app that exposes editing to users must add its own handlers and decide who is allowed to edit.

### Typical use in a decision request

```go
store := decisionpolicy.NewStore(ApiTypes.SharedDBHandle, logger)

pol, err := store.GetCurrent(ctx, "prompt_injection")
if err != nil {
	return err
}
state, _ := json.Marshal(map[string]string{"text": userMessage, "policy": pol.Content})

resp, err := client.Complete(ctx, llm.Request{
	Model:    model,
	Messages: []llm.Message{{Role: llm.RoleUser, Content: string(state)}},
	Metadata: map[string]any{"policy_id": pol.PolicyID, "policy_version": pol.Version}, // traceability
	JevQuestions: llm.JevQuestions{
		"block": {Type: "noul", Instructions: "Should `text` be blocked under `policy`?"},
	},
})
```

Record `policy_id` and `policy_version`, never just the name. A deleted policy's name can be reused by a new policy, so a name alone can point to different policies over time.

The other operations are `Create`, `Update` (name and description only), `CreateVersion`, `SetCurrentVersion`, `Delete`, `Get`, `GetByName`, `List`, `GetVersion` and `ListVersions`. Their exact behavior is in the spec.

## Known limitations

- **A policy's text can't be edited in place.** Even a typo fix creates a new version. This is deliberate: it keeps every recorded version trustworthy.
- **No hard delete.** Deleted policies stay in the database. Removing one for good is a manual database task.
- **No access control.** The store accepts any caller. Apps must check permissions before letting users change policies.
- **Postgres only**, in the `shared` schema.
- **Text only.** A policy is plain text. A JSON policy can be stored as text, but the store doesn't check that it is valid JSON.
- **Each app must add the migration itself.** If an app forgets, every call fails with an error naming the missing tables.
- **Successful reads are logged at debug level only**, so routine lookups such as `GetCurrent` on every request don't flood the logs. Changes and failures are logged at info, warning or error level.

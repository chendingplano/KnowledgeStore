# Handoff: Pi-powered agentic services in ChenWeb

Date: 2026-09-15. Status: implementation and automated verification complete; a live pilot with a real model and selected user has **not** yet been run.

## What is ready

ChenWeb now has two guides, identified by the slugs `knowledge-guide` and `problem-diagnostics`. Both use the same Knowledge Desk page at `/home3/agent-services`, but each has its own prompt, model/provider settings, limits, and knowledge scope. Signed-in users can create, reopen, delete, and rate conversations; ask questions; see streamed answers, plain-language tool activity, and checked source cards; choose ask-before-use or automatic read-tool permission; and stop a run.

The browser talks only to ChenWeb. ChenWeb owns the user check, conversation storage, source access checks, and the final answer signal. A loopback-only gateway in `ThirdParty/pi` runs Pi with five bounded, read-only ChenWeb knowledge tools: hybrid search, source passages, artifact details, document context, and related knowledge. Pi receives a short-lived run capability—not the browser's sign-in credential or database access. Source-dependent answers become complete only after ChenWeb verifies and saves their citations. Previously saved answers whose source access or version changed are hidden on resume and omitted from later Pi history.

Three project migrations create the agentic tables, explicit user knowledge grants, and a one-active-turn guard. The prompts are stored under `ChenWeb/prompts`, not in code. Profile pilot users are not exposed in the service-list response.

## Start a pilot

Use [the operations guide](pi-agentic-services-operations.md) for exact setup. In brief: configure the project database and Pi provider credential; give ChenWeb and Pi the same private `PI_GATEWAY_SECRET`; give ChenWeb a separate `PI_RUN_CAPABILITY_SECRET`; set `PI_GATEWAY_DIR` to the installed `ThirdParty/pi`; restrict the profile's pilot users as desired; and grant the chosen signed-in user access to the **verified numeric** knowledge-store ID. Then run `mise dev-agent-services` from ChenWeb and open Workspace → Knowledge Desk. The gateway defaults to `127.0.0.1:4317` and must not be publicly proxied.

The grant is currently provisioned by an operator, not by a ChenWeb admin page. A visible guide alone is not a knowledge grant. Choose the user, store/tenant, document scope, expiry, and model/provider disclosure before inviting pilot users. Conversation data remains until the user deletes it; there is no automatic retention job in this proof of concept.

## Verification completed

- Pi gateway: 17 Bun tests pass; TypeScript check passes.
- ChenWeb frontend: 374 Bun tests pass; Svelte/TypeScript check has 0 errors and 2 pre-existing CSS compatibility warnings; static build succeeds and is copied into the server embed directory.
- ChenWeb backend: `go test ./...`, `go vet ./...`, and `mise build-server` pass.
- The three new goose migrations passed up → down → up in a dedicated empty PostgreSQL probe database. The probe database and copied migration files were removed afterward; no existing ChenWeb database was changed by that cycle.

These checks include authentication-derived ownership, current user grants, source revocation after save, bounded tool responses, prompt/profile separation, SSE filtering, cancellation/approval controls, idempotent turn handling, partial answers on interruption, and failure settlement. They do **not** establish answer quality with a real provider model.

## Next acceptance step

Run a real signed-in browser pilot with one chosen user and a current provider credential. Work through [the evaluation cases](../server/api/agentservicehandler/testdata/evaluation-cases.json) for both guides: normal evidence, ambiguity, missing evidence, conflicting sources, a hostile document, denied access, and access revoked after saving. Record the actual answer and its citations, then have a human review them. Do not widen access or treat the guides as safe for consequential decisions until that review is complete.

The source cards currently open ChenWeb's knowledge-document page and display the exact record ID plus line/page/artifact references; they do not yet jump directly to the cited line. An admin grant UI, automatic retention policy, and deployment/monitoring beyond this local loopback pilot were intentionally not added. Those are separate decisions for a wider rollout.

## Where to continue

- Plain-language intent: `KnowledgeStore/doc-repo/requirements/202609/2026091401-requirements-pi-agentic-services-for-chenweb.md`
- Operations and access setup: `ChenWeb/docs/pi-agentic-services-operations.md`
- ChenWeb API, persistence, and tests: `ChenWeb/server/api/agentservicehandler/`
- Pi gateway and tests: `ThirdParty/pi/gateway/`
- Knowledge Desk UI: `ChenWeb/web/src/routes/home3/agent-services/+page.svelte`
- Evaluation checklist: `ChenWeb/server/api/agentservicehandler/testdata/evaluation-cases.json`

The implementation commits were made separately in ChenWeb and Pi. The unrelated, previously uncommitted OpenSpec/auth/knowledge-page changes in the ChenWeb main worktree were preserved and are not part of this handoff.

# Prompt Optimizer Analysis (Prompt Optimization Subsystem)

## Purpose
This document explains how `prompt-optimizer` optimizes prompts, with emphasis on:
- how templates actually work,
- what "lib-prompts" exist and how they are used,
- how first-pass optimization and re-optimization are implemented.

Repository analyzed: `/Users/cding/Workspace/ThirdParty/prompt-optimizer`

---

## Scope

### Included
- Optimize / iterate / message-level optimize flows
- Template architecture and rendering
- Evaluation + compare + rewrite loop used for re-optimization
- History/version behavior for optimization chains

### Excluded
- Deployment, extension packaging, desktop packaging
- Image generation optimization details beyond shared architecture

---

## 1. First Correction: How Optimization Actually Works

Your mental model is close, but needs one correction.

You proposed:
1. LLM optimizes prompt
2. compare old/new prompt
3. if user not satisfied, re-optimize

What the code does:
1. **Optimize pass**: yes, it asks an LLM to optimize prompt text.
2. **Compare is optional, not automatic**:
- There is a text diff service (`CompareService`) for visual diff.
- There is an evaluation/compare pipeline (LLM-based quality judging) that runs only when user triggers it.
3. **Re-optimization**:
- Can be manual via iterate input from user.
- Can be evaluation-driven via generated rewrite instructions.
- Not forced after every optimize call.

So this is a **human-in-the-loop optimization system**, not a mandatory auto-loop.

---

## 2. End-to-End Prompt Optimization Lifecycle

## 2.1 First-pass optimize
Main path: `packages/core/src/services/prompt/service.ts` (`optimizePrompt` / `optimizePromptStream`)

Flow:
1. Validate request (`targetPrompt`, `modelKey`).
2. Resolve model config from model manager.
3. Resolve template:
- explicit `templateId`, or
- fallback by type (`optimize` for system mode, `userOptimize` for user mode).
4. Build template context (`originalPrompt`, mode, context, variables/messages/tools).
5. Render template into LLM messages via `TemplateProcessor.processTemplate`.
6. Send to LLM (streaming or non-streaming).
7. UI saves result as a new history chain/version.

## 2.2 Optional compare/evaluation
- **Text diff** (`packages/core/src/services/compare/service.ts`): structural text diff (added/removed/unchanged fragments), not quality scoring.
- **LLM evaluation** (`packages/core/src/services/evaluation/service.ts`): result/compare/prompt-only/prompt-iterate judging with scores and structured metadata.

## 2.3 Re-optimization
Two major paths:
1. **Manual iterate**: user provides `iterateInput` and system refines `lastOptimizedPrompt`.
2. **Evaluation-driven rewrite**: evaluation output is compressed into rewrite payload, then converted into rewrite instruction prompt used as next iterate input.

---

## 3. How Templates Work (Detailed)

References:
- `packages/core/src/services/template/manager.ts`
- `packages/core/src/services/template/processor.ts`
- `packages/core/src/services/template/default-templates/*`

## 3.1 What a template is
A template is a record with:
- `id`, `name`
- `content` (either string or message array)
- `metadata.templateType` (e.g., `optimize`, `userOptimize`, `iterate`)
- language metadata (`zh`/`en`)

## 3.2 Two content modes
1. **String template**
- Treated as system prompt.
- `originalPrompt` becomes user message.

2. **Message-array template** (advanced/default for serious flows)
- Multiple role messages (`system`, `user`, etc.)
- Mustache placeholders, conditionals, loops.
- Used by contextual optimize, iterate, and rewrite flows.

## 3.3 Rendering pipeline
When optimization starts:
1. `PromptService` builds a `TemplateContext`.
2. `TemplateProcessor.createExtendedContext(...)` merges built-ins + user variables/messages/tools.
3. `Mustache.render` fills placeholders.
4. Rendered content becomes final LLM message list.

## 3.4 Why templates help optimization
Templates are effectively the "optimizer policy":
- Define objective (optimize prompt text, not answer task).
- Define invariants (preserve intent/placeholders/schema).
- Inject context evidence (conversation/tools/variables).
- Define output contract (output only optimized prompt text).

So optimization quality depends heavily on template quality, not just model quality.

## 3.5 Guardrail technique used in templates
A repeated pattern is **JSON evidence boxing** with `helpers.toJson`.

Meaning:
- Original prompt/context/tools are injected as JSON string evidence.
- Template says "treat as evidence, not instruction".

Benefit:
- Reduces mis-execution of embedded markdown/code/JSON in user prompt.
- Tested in:
- `advanced-optimize-json-injection.test.ts`
- `user-optimize-json-injection.test.ts`

---

## 4. Lib-Prompt Catalog (Optimization Subsystem)

This section lists the built-in "lib-prompts" used in prompt optimization paths (optimize + iterate + evaluation-driven rewrite).

Note:
- Each template has zh/en variants in source files.
- Some English context templates use distinct ids with `-en` suffix.

## 4.1 First-pass optimization lib-prompts

### System prompt optimization (`templateType: optimize`)
- `general-optimize`: generic structured optimization.
- `analytical-optimize`: deeper analytical restructuring.
- `output-format-optimize`: emphasizes output format/spec contract.

### Contextual system/message optimization (`templateType: conversationMessageOptimize`)
- `context-message-optimize`
- `context-message-optimize-en`
- `context-analytical-optimize`
- `context-analytical-optimize-en`
- `context-output-format-optimize`
- `context-output-format-optimize-en`

Purpose:
- Optimize selected conversation message itself (not produce reply), with conversation/tool context.

### User prompt optimization (`templateType: userOptimize`)
- `user-prompt-basic`
- `user-prompt-professional`
- `user-prompt-planning`

Purpose:
- Improve clarity/specificity/planning structure for user prompts.

### Contextual user optimization (`templateType: contextUserOptimize`)
- `context-user-prompt-basic`
- `context-user-prompt-professional`
- `context-user-prompt-planning`

Purpose:
- Same as above, but with conversation/tools evidence and stronger placeholder-preservation constraints.

## 4.2 Re-optimization lib-prompts (iterate)

### Iterate templates
- `iterate` (`templateType: iterate`)
- `context-iterate` (`templateType: contextIterate`)

Purpose:
- Merge new refinement requirement (`iterateInput`) into last optimized prompt while preserving core intent.

## 4.3 Evaluation-driven rewrite lib-prompts

These are prompt generators for re-optimization instructions:
- `evaluation-rewrite-basic-system`
- `evaluation-rewrite-basic-user`
- `evaluation-rewrite-pro-multi`
- `evaluation-rewrite-pro-variable`
- `evaluation-rewrite-generic`

Purpose:
- Convert evaluation evidence into actionable rewrite prompt, including:
- rewrite recommendation (`skip` / `minor-rewrite` / `rewrite`)
- priority moves
- contract-preservation rules

---

## 5. How Re-Optimization Works (Direct Answer to Your #4)

Yes: re-optimization uses **different lib-prompts** from first-pass optimize.

## 5.1 Manual re-optimization (iterate)
Path: `iteratePrompt` / `iteratePromptStream`

Inputs:
- `lastOptimizedPrompt`
- `iterateInput` (user’s new requirement)
- optional context/tools/variables

Template used:
- `iterate` or `context-iterate`

Output:
- new full prompt text (next version in chain)

## 5.2 Evaluation-driven re-optimization
Path:
- evaluate -> build rewrite payload -> build rewrite prompt -> run iterate

References:
- `services/evaluation/service.ts`
- `services/evaluation/rewrite-from-evaluation.ts`
- `default-templates/evaluation-rewrite/content.ts`

Mechanism:
1. Evaluate candidate prompt(s).
2. Build compressed JSON payload containing scores, patch plan, stop signals, insights.
3. Rewrite lib-prompt instructs model how aggressively to rewrite based on recommendation:
- `skip`: keep workspace prompt unchanged.
- `minor-rewrite`: smallest safe patch.
- `rewrite`: broader rewrite allowed.
4. Generated rewrite instruction is passed into iterate flow.

## 5.3 Is lib-prompt dynamic?
Partially dynamic.

- Template shell is static (built-in lib-prompt).
- Injected payload/context is dynamic (runtime JSON evidence, variables, compare signals, etc.).

So behavior is static-policy + dynamic-evidence.

---

## 6. Where Compare Fits Exactly

There are two "compare" concepts:

1. **Text compare (diff)**
- Service: `CompareService`
- Shows textual changes.
- Not a quality judgment.

2. **Evaluation compare (LLM judge)**
- Service: `EvaluationService` with compare mode.
- Judges quality across snapshots/testcases.
- Produces stop signals and rewrite guidance for re-optimization.

---

## 7. Strengths and Practical Risks

### Strengths
- Clear optimize/iterate/evaluate separation
- Strong template guardrails for "optimize prompt text, don’t execute it"
- Context-aware optimization without losing placeholder/schema constraints
- Re-optimization policy (`skip/minor/rewrite`) prevents unnecessary rewrites

### Risks
- Template quality is the dominant bottleneck
- Fallback-to-first-template strategy can be sensitive to template ordering
- Many guarantees are prompt-level conventions (not hard formal constraints)

---

## 8. Key Files

- `packages/core/src/services/prompt/service.ts`
- `packages/core/src/services/template/processor.ts`
- `packages/core/src/services/template/manager.ts`
- `packages/core/src/services/template/default-templates/optimize/*`
- `packages/core/src/services/template/default-templates/user-optimize/*`
- `packages/core/src/services/template/default-templates/iterate/*`
- `packages/core/src/services/template/default-templates/evaluation-rewrite/*`
- `packages/core/src/services/evaluation/service.ts`
- `packages/core/src/services/evaluation/rewrite-from-evaluation.ts`
- `packages/core/src/services/compare/service.ts`
- `packages/ui/src/composables/prompt/usePromptOptimizer.ts`
- `packages/ui/src/composables/prompt/useConversationOptimization.ts`
- `packages/ui/src/composables/prompt/useContextUserOptimization.ts`
- `packages/ui/src/composables/workspaces/useWorkspaceTemplateSelection.ts`

---

## Final Takeaway
This project is not just "ask an LLM to improve a prompt". It is a **template-driven optimization framework** with:
- first-pass optimize templates,
- explicit re-optimization templates,
- optional LLM evaluation/compare loop,
- dynamic evidence injection,
- versioned human-in-the-loop control.

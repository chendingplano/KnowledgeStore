---
title: Keyword Rewrite Rules
language: en
format: markdown
version: 1.0
status: active
author: Not specified
owner: Not specified
audience: ChenWeb administrators and knowledge curators
create-time: 2026-08-23T09:50:00-05:00
last-modify-time: 2026-08-23T09:50:00-05:00
keywords: keyword rewrite, keyword normalization, aliases, Tier 3, exact matching, scopes, ChenWeb administration
---

# Keyword Rewrite Rules

Keyword rewrite rules let an administrator define a safe, explicit alias for a keyword surface. When the normal keyword lookup does not find a match, Tier 3 can replace the entire input with the rule's replacement and retry the deterministic lookup.

This manual is for ChenWeb administrators and knowledge curators who maintain keyword behavior. It explains when a rule is useful, how matching works, and how to manage rules from **Development → System Admin → Keyword Normalization → Rewrite Rules**.

## What a rewrite rule does

A rule connects one exact input (`pattern`) to another exact input (`replacement`) within a `scope`. For example:

| Pattern | Replacement | Scope |
| --- | --- | --- |
| `acct.` | `account` | `_` |
| `temp reading` | `temperature reading` | `lab-1` |

If the whole incoming surface is `acct.` in scope `_`, Tier 3 may retry lookup with `account`. The rule does not create a concept and does not guarantee that the replacement resolves successfully.

## Matching behavior and limits

Rules have deliberately narrow behavior:

- Matching is against the entire raw input, not a word or substring.
- Matching is case-sensitive. `Account` and `account` are different.
- The scope must exactly match the request's scope.
- Rules are ordered by rule ID. The first matching enabled rule wins.
- Only one rule is applied. Rules are not chained.
- Patterns are literal. Regular expressions, capture groups, backreferences, and substring matching are not supported.
- Disabled rules are preserved but do not run.

Because the first matching rule wins, avoid creating two enabled rules with the same pattern and scope. If an earlier rule ID already matches, a later rule will be shadowed.

## When to use a rule

Use a rewrite rule when a known, stable surface is an exact alias for another surface and the alias should apply consistently in a particular scope. Examples include a documented abbreviation, a legacy label, or a controlled spelling used by one data source.

Do not use a rule to compensate for broad misspellings, arbitrary text fragments, case variations, or behavior that requires several transformations. Prefer maintaining the keyword concepts and surfaces when the alternate surface should be a normal, directly searchable label.

## Create a rule

1. Open **Development → System Admin → Keyword Normalization → Rewrite Rules**.
2. Select **New Rule**.
3. Enter a unique rule ID. It is the rule's identity and cannot be changed later.
4. Enter the pattern exactly as it should arrive. Do not add or remove whitespace unless that is intended.
5. Enter the replacement exactly as Tier 3 should retry.
6. Select a known scope, or choose **Custom…** and enter a nonblank scope.
7. Enter provenance, such as `human:`, to record why the rule exists.
8. Leave **Enabled** off while reviewing the rule. Enable it only when the alias is ready to affect lookup.
9. Review the hypothetical preview and choose **Save Rule**.

The preview is illustrative. It shows the whole-input rewrite, scope, and enabled state; it does not run the resolver or claim that the replacement currently resolves to a concept.

## Edit a rule

Choose **Edit** in the table. The rule ID is shown as immutable. You can replace the pattern, replacement, scope, provenance, or enabled state. The server validates the complete replacement and preserves the rule ID.

Pattern and replacement whitespace is meaningful. The page checks that they are not blank and rejects parentheses and backslashes in patterns, but it does not silently trim the submitted values.

## Enable, disable, search, and filter

Use the status control in a row to enable or disable a rule after confirmation. You can also change the enabled checkbox while editing. Disabling is the way to stop a rule while retaining its history; rules are not deleted from this page.

The table search checks rule ID, pattern, replacement, and provenance. The scope filter selects one exact scope, and the status filter shows all, enabled, or disabled rules. **Refresh** reloads the current server state after a change or when another administrator may have updated the table.

## Risks and review checklist

An enabled rule changes only the Tier 3 retry path, but it can change which concept is selected when the replacement has a match. Before enabling a rule, confirm:

- the exact input, including capitalization and whitespace;
- the intended scope;
- that the replacement is the desired canonical surface;
- that no lower rule ID shadows the draft;
- that the rule is not broader than the source data requires.

If a rule produces an unexpected result, disable it first. The original row remains available for review and later editing.

## Access

The administration reads and writes require an authenticated owner, administrator, or user with the `admin` or `root` role. The page's navigation visibility is not a substitute for server authorization.

## Change Log

| Version | Timestamp | Author | Reason | Summary |
| --- | --- | --- | --- | --- |
| 1.0 | 2026-08-23T09:50:00-05:00 | Not specified | Initial manual | Explained exact, scope-specific keyword rewrite rules and the ChenWeb administration page for creating, editing, enabling, disabling, searching, and filtering them. |

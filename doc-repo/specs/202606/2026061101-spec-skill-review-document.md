# 1. Create 'Review Document' Skill

- DocID: `doc-2026061101`
- **Status:** Active
- **Date:** 2026-06-11
- **Deciders:** ChenWeb
- **Tags:** Skill

# 2. Change Logs
- Created by Chen Ding on 2026/06/11

# 3. Context
The system has a knowledgebase that is built on the corpus of standards, technical documents, etc.
Documents are parsed into text form as needed form and then converted to line files (refer to [1]).

Refer to [3] for for more information about the knowledgebase.

Given a technical document, review it in in the aspects specified in [3]
to identify the discrepancies based on the ground truth in the system knowledgebase.

This skill is a coordinator. There should be a skill that is specialized in
reviewing the document in one aspect in [3].

Aspects are prioritized into 'High', 'Medium' and 'Low'. Users can choose 

## References
[1] 2026042101-spec-line-file.md

[2] 202606/2026061105-spec-knowledgestore-explore-search.typ

[3] KnowledgeStore/doc-repo/202606/2026061102-spec-document-review-checklist.md

# Basic Requirements
- This is a data processor ([1])
- Refer to Section "Add New Doc Processor" in [1] for the steps to add a new processor
- The doc processor uses an LLM to extract entities and relations from chunks ([2])
- Create a prompt and save it to 'ChenWeb/prompts'
- Use env var EXTRACT_ENTITY_RELATION_MODEL_NAME for the primary model name
- Use env var EXTRACT_ENTITY_RELATION_FALLBACK as the fallback model name
- Use env var EXTRACT_ENTITY_RELATION_PROMPT as the prompt
- Define and create the table 'kb.entities'
- Define and create the table 'kb.relations'
- Both 'kb.entities' and 'kb.relations' support full-text search, similar to [3]
- Save entities to 'kb.entities' and to the file '.entities' in its artifact directory, similar to the '.metrics' file in [3]
- Save relations to 'kb.relations' and to the file '.relations' in its artifact directory, similar to '.metrics' file in [3]
- The implementation is very similar to [3], but `entities` and `relations` do not extract category paths, thus no index them to the ARTIFACT_WEB_DIR as [3] does.
- Create a spec markdown document `extract-entity-relation-spec.md`
- Create a implementation markdown document `extract-entity-relation-impl.md`
- Create a test markdown document `extract-entity-relation-test.md`
- Output should be strict JSON
- All textual attributes MUST be in its input language and add the '_en' attribute that is the English translation of the original textual attribute if the input language is not English

IMPORTANT NOTES
- If combining extraction and translation into the same LLM call is too much for LLMs, consider using two passes.

# References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md

[2] KnowledgeStore/Capsules/coding-capsules/chunking/+CAPSULE.md

[3] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md
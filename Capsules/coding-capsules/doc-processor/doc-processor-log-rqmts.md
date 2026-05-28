# Purposes
Log doc processor activities to tables and build a GUI to view and maintain the logs.

# Requirements
Data processors are defined in [1]. 

## Activities to Log
### LLM Call Logging
It generates one record for each artifact extracted/generated:
- call_reason
- doc_proc_name: the doc processor name
- model_names: the model name
- prompt_name: the prompt name
- entry_type: 'llm_call'
- pass: an integer that signifies the pass, such as 1 (for Pass 1), 2 (for pass 2),
- llm_call_id: a unique ID that identifies an LLM call
- activity_name, such as 'extract_metrics_candidates', 'enrich_semantic_projections'
- artifact, a JSON field for the extracted/generated artifact
- errors
- extra_info: a JSON reserved for activity specific customized information
- Start time
- End time

### Doc Processor Summary Logging
It generates one record per doc processor invocation:
* doc_processor_name
* model_names: all the model names used
* prompt_name: all the prompt names used
* entry_type: 'doc_proc_summary'
* pass: ignore
* llm_call_id: ignore
* activity_name: ignore
* artifact: ignore
* errors
* extra_info: the summary of the doc processor invocation, as a JSON doc
* Start time
* End time

 Note that summaries are doc processor specific. For instance, the summary for 
 extracting metric doc processor should include the total number of metrics
 retrieved, the number of fallbacks, the number of failed LLM calls, etc.
 
## Create Table
Define and create the table 'kb.doc_proc_logs'

## Create Documents
- Create a spec markdown document `doc-processor-log-spec.md`
- Create a implementation markdown document `doc-processor-log-impl.md`
- Create a test markdown document `doc-processor-log-test.md`

## Create Frontend Pages
Create frontend pages to:
- View LLM activity logs
- Configure the retention plan to remove log entries automatically
- Search logs
- Add the pages to the menu 'ChenWeb::/home3/, "SYSTEM ADMIN => Doc Processor Logs"

# Specifications
Refer to [2].

# Implementations
Refer to [3].

# Test
Refer to [4].

# References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md

[2] KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-log-spec.md

[3] KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-log-impl.md

[4] KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-log-test.md
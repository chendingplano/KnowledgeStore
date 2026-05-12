## Doc Processing Pipeline
- Detect changes in the staging directory
- Create a record and insert it to 'kb.inputs'. Publish a 'kb.pdf.staged' event to JetStream
- Doc processor `PDF Parser` is triggered by the event. It parses the document and publish a 'kb.pdf.parsed' event
- Doc processor `Result Converter` is triggered by the event. It converts the JSON results from the PDF Parser into a line file (refer to 'spec-line-file.md'). It publishes 'kb.line-file-generated'
- A number of doc processors are triggered by the event 'kb.line-file-generated'. Refer to "Doc Processors" section in [1].

The pipeline by default executes all the processors unless the events otherwise specifies.
More specifically, the 'kb.line-file-generated' event may hand-pick the proccors to execute by the 'operation'
attribute. Refer to the 'Processor Name' column of the table in the "Doc Processors" section in [1]

## Doc Processing Status
Each record in 'kb.inputs' identifies a document. 'kb.inputs.status' manages its status. Refer to [2] for 'kb.inputs' table schema and its 'kb.inputs.status'.

The sytem may process multiple, normally up to 10, concurrent doc processing threads.

## Dashboard 
### Show Pipelines
- For each processing thread, show the pipeline and mark the current stage
- When mouse hovers over a node in a pipeline, show the node details
- Stop a processing thread
- Restart a processing thread, hand-pick the processors to re-run. Default: re-run all.

### Manual Launch Pipelines
- Search records in 'kb.inputs'
- Hand-pick the doc processors to run. Default: run all
- Confirm before launching

## References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md 

[2] KnowledgeStore/DevDocuments/Specs/table-schemas/table-kb-inputs.md
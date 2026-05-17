# Schema
| Field Name | Required | Explanation |
|-----------|---------|------------|
| id | required | an auto-incremented integer |
| metric_id | required | string, uniquely identify metrics in this table |
| event_id | optional | the JetStream event id |
| input_record_id | required | the input record id |
| metric_name | optional | a short description for the metric, in the original language |
| metric_name_en | optional | the English version |
| source_line_spans | required |  the line numbers of the source text, such as [10-12, 15, 20-22] |
| metric_subject | optional | the metric's subject in the original language |
| metric_subject_en | optional | the English version |
| metric_desc | optional | the metric's description in the original language |
| metric_desc_en | optional | the English translation |
| metric_context | optional | a summary of the context in which the metric is defined in the original language |
| metric_context_en | optional | the English translation |
| metric_keywords | optional | the keywords in the original language |
| metric_keywords_en | optional | the English translation |
| model_name | optional | the name of the model to extract the metrics |
| prompt_name | optional | the name of the prompt used to extract the metrics |
| location_type | optional | "sentence|bullet|table_row|table_cell|heading_context|mixed" |
| metric_unit | optional | the metric's unit in the original language|
| metric_unit_en | optional | the English translation |
| metric_value | optional | the metric's value |
| value_data_type | optional | the metric value data type |
| value_range_type | optional | the value range type |
| value_class | optional | the value classification |
| value_class_en | optional | the English version of the value classification |
| formula_or_definition | optional | formula or explicit definition if present, otherwise null |
| threshold_or_target | optional | target / threshold / acceptable limit if present, otherwise null |
| measurement_frequency | optional | the metric's measure frequency |
| confidence | optional | the confidence |
| is_explicit_metric | optional | true if the document clearly defines it as a metric; false if inferred but still strongly supported |
| table_name_or_section | optional | table caption, section title, or nearest heading if available |
| reasoning_tags | optional | the extraction reasoning tag |
| ext_info | optional | for additional information |
| created_at | optional | timestamptz, DEFAULT now(), not null |
----

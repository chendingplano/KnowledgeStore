# Overview
Artifacts are connected in various forms. This document focuses on connecting artifacts
through shared lines.

## Connect Topics and Metrics
If a metric and a topic of the same document (identified by `record_id`) 
share at least one line (by line numbers), create a connection:

## 'kb.topic_conns'
It stores connections whose sources are topics and targets can be docs and artifacts.

```text
record_id: 123
source_id: the topic id
target_id: the artifact id
relation_name: the relation type
relation_method: 'calculated'
semantic_signature: a descriptive passage that is used to enhance the searchability
extra_info: a JSON for any additional information
create_time: the creation time
```

## 'kb.metric_conns'
It stores connections whose sources are metrics and targets can be docs and artifacts.

```text
record_id: 123
source_id: the metric id
target_id: the artifact id
relation_name: the relation type
relation_method: 'calculated'
semantic_signature: a descriptive passage that is used to enhance the searchability
extra_info: a JSON for any additional information
create_time: the creation time
```

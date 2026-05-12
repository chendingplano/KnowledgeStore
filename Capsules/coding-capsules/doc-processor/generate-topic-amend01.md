# Requirements
This is an amendment to 'spec-chunking-topic.md'.

In the current implementation, topic-driven chunks are stored in "ARTIFACT_DIR + '/<group_id>/<record_id>/topics.txt'".

This amendment requires:
1. Categorize a topic in multi-level categories (done by LLMs). Use snake-casing for category names.
2. All topic categories form a Category Tree
3. Store the category tree as a file tree, where each inner node in the category tree maps to a directory or sub-directory
   and leaf nodes map to file names (`<leaf>.txt`).
4. Keep `topics.txt` as it is. After `topics.txt` is created, extract each line in `topics.txt` and save it to the file tree.
5. Leaf nodes in the file tree are files in the following format:
```text
<record_id>\t<topic-type>\t<lines>\t<keywords>\t<topic>
```
Below is an example:
```text
53 list	[215-227]	[scoring items, safety evaluation, seismic design]	Scoring items and specific rules for evaluating safety, including seismic design and protective measures against falling objects.
```
Saving a topic to its leaf file MUST be idempotent. If a record with `record_id = 53` is re-processed, saving to leaf files MUST replace existing entries whose `record_id == 53` with the new content.

# Rules
- Category names MUST be descriptive
- Category names use snake-casing, max length 64 characters
- Category maximum depth is 6
- If a category path is invalid (missing, non-descriptive, too deep, or segment too long):
  1. Attempt to build a fallback category path from the topic's keywords (3–5 descriptive, normalized keywords).
  2. If no usable keywords are available, route the topic to `uncategorized/<topic_type>.txt`.
  3. Always emit a `WARN` log ("topic category fallback applied") with the `reason` and the resulting `fallback_category` path.
- Output MUST be deterministic for the same input (same paths and same row ordering).
- Legacy flat output file `topics.txt` MUST be retained and continue to be generated.

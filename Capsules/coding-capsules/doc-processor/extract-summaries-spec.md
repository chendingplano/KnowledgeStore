# Extract summaries

`extract_summaries` is a configurable Phase B processor depending only on
`chunking`. It runs Sumy locally, without LLM calls, against each existing chunk.
It produces one level-0 row per chunk in `kb.ex_summaries`. It does not build a
summary tree or translate, embed, categorize or infer requirements.

## Configuration

- `EXTRACT_SUMMARIES_ALGORITHM`: `lexrank` (default), `textrank`, `lsa`, `luhn`,
  or `sumbasic`. Unknown values fail the selected processor.
- `EXTRACT_SUMMARIES_SENTENCES`: positive integer, default 3, at most 100.
- `EXTRACT_SUMMARIES_TIMEOUT`: positive Go duration, default `2m`, per document
  worker invocation. Cancellation terminates the Python process.
- `SUMY_PYTHON`: Python executable, default `python3`. Install the locked environment
  in `ChenWeb/python/sumy/` and set this to its interpreter in deployment.

Invalid settings fail only when this processor runs; they do not prevent an
unrelated processor from starting. List `extract_summaries` in the configured
`required_processors` to make it available. Default selection remains explicit.

## Input and extraction

Read the in-memory chunk buffer when available, otherwise read the canonical line
file and existing `.chunks` artifact. Process only original level-0 chunks; never
submit higher-level grouped chunks. Never re-chunk or merge documents. Include
overlap context. Exclude image-only lines; retain short lines, bullets, headings,
numbers and table text. A chunk with no usable textual content has an empty extract.

Segment the complete chunk text, so a sentence may cross source lines. Use Sumy's
sentence ranking and output selected sentences in original order. Return exact
source text and original line/Unicode-code-point offsets for each selected sentence.
Map duplicate sentences by occurrence, not string identity. Keep an unterminated
Chinese tail, which Sumy sentence splitting otherwise omits. No usable ranking vocabulary or an empty ranked result triggers source-order
selection and records the reason in the stored per-chunk configuration. Fail rather than save
an ungrounded or altered sentence. Use Chinese tokenization for Chinese chunks,
English for English chunks; explicit English/Chinese document language takes precedence,
with content detection for empty/mixed metadata. Unsupported explicit languages
fail visibly rather than silently tokenizing as English.

Dependencies/tokenizer data must be provisioned before processing; workers never
download packages or NLTK data at request time. One worker invocation processes all
chunks sequentially, so matrix scope is one chunk and Python initialization is
amortized over the document.

## Persistence

Create `kb.ex_summaries` through a project goose migration, with the current
`kb.summaries` fields plus nonempty `algorithm`, `source_sentence_spans` (exact
selected evidence), and `extraction_config` (sentence count, dependency versions, input digest and worker version).
`source_line_spans` contains the selected evidence's compact line ranges; an empty
extract has `[]`. `summary_level=0`, `summary_seq_no=chunk.SeqNo`, `child_summary_ids=[]`.
Unused translation and keyword fields remain empty. `language` identifies the
tokenization language used for that chunk.

Uniqueness is `(input_record_id, algorithm, summary_level, summary_seq_no)` and
`summary_id` includes record ID, algorithm and chunk sequence. Reruns atomically
replace only the chosen `(record, algorithm)` output after all chunks succeed.
Other algorithms and `kb.summaries` remain intact. The response must contain exactly
one result for each submitted chunk, with unique matching sequence numbers,
supported/matching language, matching algorithm/version, and at most the configured
number of sentences. Go verifies every sentence and its summary against the
submitted source before beginning replacement. Failure/stop retains previously
committed extracts. A record row lock serializes replacement for the same record;
input deletion cascades via the foreign key. Capture source/chunk fingerprints
before extraction and recheck present files and the context buffer under that lock
before deleting old rows; reject detected changes. Save the exact worker-input
digest with dependency versions for audit. Filesystem writes are not transactional
with PostgreSQL, so this recheck does not coordinate arbitrary concurrent external
file writers; reprocessing the same document should be serialized operationally.

The retained summary columns are `id`, `summary_id`, `input_record_id`,
`summary_level`, `summary_seq_no`, `source_line_spans`, `child_summary_ids`,
`keywords`, `keywords_en`, `summary_text`, `summary_text_en`, `language`,
`search_document`, `search_vector`, `created_at` and `updated_at`. New fields are:

| Column | Type | Meaning |
| --- | --- | --- |
| `algorithm` | `TEXT NOT NULL` | Canonical Sumy algorithm; part of the unique chunk identity |
| `source_sentence_spans` | `JSONB NOT NULL` | Array of `{text, spans: [{line, start, end}]}` for selected sentences |
| `extraction_config` | `JSONB NOT NULL` | Sentence count, package versions, worker version, exact input digest and optional fallback reason |

The `source_sentence_spans` offsets use Unicode code points, inclusive start and
exclusive end, within the original canonical line content. Selected text remains
in source order. Each algorithm's stored input digest identifies its extraction
input; after rechunking, rerun other algorithms before treating their retained
outputs as current.

Maintain the same table-local search-document/vector trigger behavior as
`kb.summaries`; global hybrid-search registration is outside this processor's scope.

## Status and logs

Use operation `extract_summaries` in `kb.inputs.status`. Include algorithm, sentence
budget, number of chunks/summaries, start time, elapsed milliseconds, progress and
`active|success|failed|stopped`. Status read-modify-write uses the shared record lock.
Final status/log writes use a bounded background context after cancellation. Emit
a `doc_proc_summary` log with processor name, algorithm and counts; no model/token
usage is reported. Never report success before the database transaction commits.

## Acceptance

Verify actual Sumy on English, Chinese, repeated and split sentences, empty/image
chunks and each supported algorithm. Verify replacement isolation, rollback,
failure/stop behavior, registration and both startup paths. Test the migration
up/down/up against an isolated database/schema, including cascade and uniqueness.
The frozen quality benchmark remains unchanged. Extraction accuracy and benchmark
quality are separate: selecting exact words cannot guarantee requirement coverage.

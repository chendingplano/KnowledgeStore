#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#show heading: it => {
  set text(fill: blue) if it.level == 1
  if it.numbering != none {
    counter(heading).display(it.numbering)
    h(0.5em) // Adds a little gap after the number
  }
  it.body
}

#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "SemOS Knowledge Base"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

#let frontmatter = (
  file_type: "typst",
  logical_name: "SemOSKnowledgeBase",
  file_id: "2026061601-spec",
  content_type: "spec",
  document_date: "2026/06/16",
  keywords: [SemOS, Knowledge System],
)

= SemOS Knowledgebase
SemOS knowledgebase is built on a corpus of documents, mostly standards and technical documents. 
Documents can be in various format, including PDF, Doc files. 
Documents are parsed into line files (refer to [1]).

Each document is a Searchable Object. Documents are stored in the table `kb.inputs`,
identified by `kb.inputs.id` (`record_id`), which is an auto-incremented integer.

== Documents in Files
A document, its line file, its chunks, and all its artifacts are stored in a specific directory:
```text
    Artifacts/<group_id>/<record_id>/
```
where `<group_id>` = floor(`record_id` / 1000).

The directory contains the following files and directories:
#table(
    columns: 2,
    align: left,
    [File Name], [Explanation],
    [images/], [A directory that lists all the images extracted from the doc for pictures, tables, and formulas],
    [`<filename>`\_`<parser_name>`.chunks], [List the document chunks ],
    [`<filename>`\_`<parser_name>`.entities], [All the entities extracted by LLM from this document ],
    [`<filename>`\_`<parser_name>`.json], [The parse result in JSON ],
    [`<filename>`\_`<parser_name>`.metrics], [ALl the metrics extracted by LLM from this document ],
    [`<filename>`\_`<parser_name>`.origin], [The original line file of the document ],
    [`<filename>`\_`<parser_name>`.provisions], [All the compliance provisions extracted by the LLM from this document ],
    [`<filename>`\_`<parser_name>`.relations], [All the relations extracted by the LLM from this document ],
    [`<filename>`\_`<parser_name>`.scene_blocks], [All the scene blocks extracted by the LLM from this document ],
    [`<filename>`\_`<parser_name>`.semantic_projections], [All the semantic projections extracted by the LLM from this document],
    [`<filename>`\_`<parser_name>`.inventory_items], [All the inventory items extracted by the LLM from this document],
    [`<filename>`\_`<parser_name>`.topics], [All the topics extracted by the LLM from this document],
    [`<filename>`\_`<parser_name>`.txt], [The line file for the document],
    [`<filename>`], [The original file ],
    [summary\_\*.txt], [The summary files, one level 0 summary per chunk, one level 1 summary per 8 level 0 summaries, etc.. File name format: `summary_<level>_<seqno>`]
)
where 
- `<filename>` is the root (i.e., without its '.ext') of `kb.inputs.file_name` (e.g., `kb.inputs.file_name` = 'Artifacts/0/387/1752338412.3225222.pdf', `<filename>` = '1752338412.3225222')
- `<parser_name>` = `kb.inputs.parser_name`

In the above, file name format is:
```text
<orig_filename>_<parser_name>.<extention>
```
where `<orig_filename>` is the root of `kb.inputs.staging_filename`, `<parser_name>` = `kb.inputs.parser_name`.

== Documents and Chunks
=== Documents
Documents are stored in `kb.inputs`. Document searchability and explorability
are done through artifacts.

=== Chunks
Big documents are broken down into chunks based on size and content 
integrity (refer to [2]). Chunks are stored in `kb.chunks`. 
Chunk searchability and explorability are done through related artifacts.

== Artifacts
=== Entities
- Extracted by LLM based on chunks
- Saved in `kb.entities`.
- Identified by `<record_id>` + 'ent' + `<seqno>`, such as '416_ent_1'.
- Added to `kb.search_artifacts`.
- Searchability through the hybrid search: BM25 + Vector Search + RRF Fusion.

*Connectivity*
- Connect to chunks by shared line numbers
- Connect to other artifacts of the same document by shared line numbers
- Connect to other artifacts by similarity (i.e., the hybrid search algorithm)
- Connect to relations by shared entity ids.
- Connect to entity categories
- Connect to other entities through entity categories
- Connect to other relations through the relation categories of its relation

=== Relations
- Extracted by LLM based on chunks
- Saved in `kb.relations`.
- Identified by `<record_id>` + 'rel' + `<seqno>`, such as '416_rel_21'.
- Added to `kb.search_artifacts`.
- Searchability through the hybrid search: BM25 + Vector Search + RRF Fusion.

*Connectivity*
- Connect to chunks by shared line numbers
- Connect to other artifacts of the same document by shared line numbers
- Connect to other artifacts by similarityh (i.e., the hybrid search algorithm)
- Connect to entities by shared entity ids.
- Connect to relation categories
- Connect to other relations through relation categories
- Connect to other entities through the entity categories of its endpoints

=== Inventory Items
- Extracted by LLM based on chunks
- Saved in `kb.inventory_items`.
- Identified by `<record_id>` + 'inv' + `<seqno>`, such as '416_inv_1'.
- Added to `kb.search_artifacts`.
- Searchability through the hybrid search: BM25 + Vector Search + RRF Fusion.

*Connectivity*
- Connect to chunks by shared line numbers
- Connect to other artifacts of the same document by shared line numbers
- Connect to other artifacts by similarityh (i.e., the hybrid search algorithm)
- Connect to entities by shared entity ids.
- Connect to inventory item categories
- Connect to other inventory items through inventory item categories

=== Metrics
- Extracted by LLM based on chunks
- Saved in `kb.metrics`.
- Identified by `<record_id>` + 'mtc' + `<seqno>`, such as '416_mtc_1'.
- Added to `kb.search_artifacts`.
- Searchability through the hybrid search: BM25 + Vector Search + RRF Fusion.

*Connectivity*
- Connect to chunks by shared line numbers
- Connect to other artifacts of the same document by shared line numbers
- Connect to other artifacts by similarityh (i.e., the hybrid search algorithm)
- Connect to metric categories
- Connect to other metrics through metric categories

=== Compliance Provisions
- Extracted by LLM based on chunks
- Saved in `kb.provisions`.
- Identified by `<record_id>` + 'prv' + `<seqno>`, such as '416_prv_1'.
- Added to `kb.search_artifacts`.
- Searchability through the hybrid search: BM25 + Vector Search + RRF Fusion.

*Connectivity*
- Connect to chunks by shared line numbers
- Connect to other artifacts of the same document by shared line numbers
- Connect to other artifacts by similarityh (i.e., the hybrid search algorithm)

=== Scene Blocks
- Extracted by LLM based on chunks
- Saved in `kb.scene_objects`.
- Identified by `<record_id>` + 'sbk' + `<seqno>`, such as '416_sbk_1'.
- Added to `kb.search_artifacts`.
- Searchability through the hybrid search: BM25 + Vector Search + RRF Fusion.

*Connectivity*
- Connect to chunks by shared line numbers
- Connect to other artifacts of the same document by shared line numbers
- Connect to other artifacts by similarityh (i.e., the hybrid search algorithm)

=== Semantic Projections
- Extracted by LLM based on chunks
- Saved in `kb.semantic_projections`.
- Identified by `<record_id>` + 'smp' + `<seqno>`, such as '416_smp_1'.
- Added to `kb.search_artifacts`.
- Searchability through the hybrid search: BM25 + Vector Search + RRF Fusion.

*Connectivity*
- Connect to chunks by shared line numbers
- Connect to other artifacts of the same document by shared line numbers
- Connect to other artifacts by similarityh (i.e., the hybrid search algorithm)

=== Summaries
- Extracted by LLM based on chunks
- Saved in `kb.summaries`.
- Identified by `<record_id>` + 'smp' + `<level>` + `<seqno>`, such as '416_sum_0_0001'.
- Added to `kb.search_artifacts`.
- Searchability through the hybrid search: BM25 + Vector Search + RRF Fusion.

*Connectivity*
- Connect to chunks by shared line numbers
- Connect to other artifacts of the same document by shared line numbers
- Connect to other artifacts by similarityh (i.e., the hybrid search algorithm)

=== Topics
- Extracted by LLM based on chunks
- Saved in `kb.topics`.
- Identified by `<record_id>` + 'tpc' + `<seqno>`, such as '416_tpc_1'.
- Added to `kb.search_artifacts`.
- Searchability through the hybrid search: BM25 + Vector Search + RRF Fusion.

*Connectivity*
- Connect to chunks by shared line numbers
- Connect to other artifacts of the same document by shared line numbers
- Connect to other artifacts by similarityh (i.e., the hybrid search algorithm)

== Artifact Categories
The following artifacts are categorized into artifact categories. 
Each artifact has one or more categories.
- Metrics
- Inventory Items
- Entities
- Relations 

All artifact categories are stored in `kb.artifact_categories`, identified
by (`kb.artifact_categories.category_type`, `kb.artifact_categories.category_key`).

An artifact category serves as a class. The relation between an artifact and
its instances are stored in the relation table `kb.artifact_connections`.

== Artifact Relations
Artifacts can be connected/related through:
- Similarith (BM25 + vector search + RRF fusion)
- Through special mechanisms (see below)
- Through category trees

=== Relations by Similarity
This is achieved by the hybrid search: BM25 + vector search + RRF fusion
over `kb.search_artifacts`.

=== Relations by Special Mechnisms
Currently, the system supports the following types of relations 
through special mechanisms:
#table(
    columns: 2,
    align: left,
    [Method], [Explanation], 
    [through `kb.relations`], [connect two entities: (subject, predicate, object)],
    [through sharing line numbers], [connect artifacts in the same document]
)

Artifact relations are stored in `kb.artifact_connections`.

=== Relations through Category Tree
Documents are broken down to chunks. The system generates a semantic projection for 
each chunk. Semantic projections are categorized by one or more category paths.
Category paths form a Category Tree under ARTIFACT_WEB_DIR.

Each subdirectory in ARTIFACT_WEB_DIR may have the following files:
#table(
    columns: 3,
    align: left,
    [File Name], [Required], [Explanation], 
    [`metadata.txt`], [required ], [ the metadata about the node],
    [`inventory_items.txt`], [ optional], [ list all the inventory items that fall in this node],
    [`metrics.txt`], [ optional], [ list all the metrics that fall in this node],
    [`semantic_projections.txt`], [ optional], [ list all the semantic projections that fall in this node],
    [`scenes.txt`], [ optional], [ list all the scene blocks that fall in this node],
    [`summaries.txt`], [ optional], [ list all the scene blocks that fall in this node],
    [`provision.txt`], [ optional], [ list all the scene blocks that fall in this node],
    [`topics.txt`], [ optional], [ list all the scene blocks that fall in this node],
    [`entities.txt`], [ optional], [ list all the scene blocks that fall in this node],
    [`relations.txt`], [ optional], [ list all the scene blocks that fall in this node]
)

== Hybrid Search on Artifacts
Table `kb.search_artifacts` schema is:

```sql
CREATE TABLE kb.search_artifacts (
	artifact_type text NOT NULL,
	artifact_id text NOT NULL,
	input_record_id int8 NOT NULL,
	source_row_id int8 NULL,
	primary_label text DEFAULT ''::text NOT NULL,
	secondary_label text DEFAULT ''::text NOT NULL,
	search_document text DEFAULT ''::text NOT NULL,
	search_vector tsvector DEFAULT ''::tsvector NOT NULL,
	snippet_basis text DEFAULT ''::text NOT NULL,
	source_title text DEFAULT ''::text NOT NULL,
	source_filename text DEFAULT ''::text NOT NULL,
	category_paths jsonb DEFAULT '[]'::jsonb NOT NULL,
	source_line_spans jsonb DEFAULT '[]'::jsonb NOT NULL,
	semantic_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	embedding_text text NULL,
	embedding public.vector NULL,
	keywords _text DEFAULT '{}'::text[] NOT NULL,
	CONSTRAINT search_artifacts_pkey PRIMARY KEY (artifact_type, artifact_id),
	CONSTRAINT search_artifacts_input_record_id_fkey FOREIGN KEY (input_record_id) REFERENCES kb.inputs(id) ON DELETE CASCADE
)
PARTITION BY LIST (artifact_type);
```

= References
[1] 2026042101-spec-line-file.md

[2] 2026060901-spec-chunking.md

# Non-generative summarization and the SemOS benchmark

**Date:** 2026-10-21
**Scope:** Options for reducing summary-generation cost, the benchmark now built, and the evaluation still required.
**Code root:** `ChenWeb/benchmark/summaries/`
**Implementation commit:** ChenWeb `896e763703e32670b8902035b10f485fe38638f4`

## Summary

SemOS may reduce summarization costs by selecting useful passages with classical algorithms instead of generating every summary with a language model. Selected passages can preserve the source wording and evidence, but they can still mislead by omitting a condition, exception or important requirement. The potential savings and summary quality have not yet been established for the SemOS corpus.

An offline benchmark is now built and frozen before candidate algorithms are implemented or tuned. It contains English, Chinese and mixed-language cases, fixed output budgets, source-backed annotations, and checks for evidence loss. It also provides a separate human-review protocol for comparing generated summaries with extracts. The current real-document pilot comes from one standard, so it cannot establish production quality across the corpus.

## Details

### 1. Extraction, generation and model dependencies

| Aspect | Extractive summarization | Abstractive summarization |
| --- | --- | --- |
| Output | Select source passages | Generate new wording |
| Requires an LLM? | No; classical methods work, but an LLM can also select passages | No instruction-tuned LLM is required; task-specific generative models can also summarize |
| Source wording | Preserved when extraction and normalization are faithful | Usually rewritten |
| Main accuracy risks | Missing evidence, detached context, incorrect source mapping | Unsupported claims, changed meaning, missing evidence |
| Cost | Depends on algorithm, preprocessing and input size | Depends on model, input/output size and deployment |
| Candidate use | Evidence-oriented extracts and browsing | Readable synthesis and explanations |

Extractive versus abstractive describes output behavior. It does not by itself describe model size, whether neural models are used, or whether inference calls a paid API. BART and PEGASUS are examples of task-specific encoder-decoder models that generate text; using them still introduces generative inference costs.

### 2. Candidate open-source projects

These are candidates for evaluation, not production selections or validated quality rankings.

| Project | Approach | Dependencies and evaluation status |
| --- | --- | --- |
| [Sumy](https://github.com/miso-belica/sumy) | LexRank, LSA, Luhn, TextRank, SumBasic | No generative model required. Proposed first classical baseline; LexRank needs NumPy and language-specific tokenization resources. |
| [PyTextRank](https://github.com/DerwenAI/pytextrank) | TextRank, PositionRank, TopicRank and related phrase ranking | Ranking is non-generative. Its documented setup loads a trained spaCy NLP pipeline, so it is not dependency-free or necessarily non-neural end to end. |
| [summa](https://github.com/summanlp/textrank) | TextRank | Another classical implementation to consider if it adds value beyond the initial baselines. |
| [BERT Extractive Summarizer](https://github.com/dmmiller612/bert-extractive-summarizer) | Sentence embeddings and clustering | Requires neural inference. Better semantic coverage is a hypothesis to test; it is not a mandatory step before trying generation. |
| [SumSimple](https://github.com/AmirTahaMim/SumSimple) | FastAPI wrapper around Sumy | Unsuitable as-is for standards: its preprocessing removes lines containing `*` or fewer than 50 words. Short requirements and table content may disappear before ranking. |

The SumSimple behavior is visible in [`_clean_text`](https://github.com/AmirTahaMim/SumSimple/blob/main/main.py). Prefer direct library integration over adopting that preprocessing. For reproducible evaluation, pin package/model versions and record tokenizer resources and configuration.

### 3. How the classical methods work

LexRank ranks sentences by centrality in a sentence-similarity graph. Sumy's implementation thresholds similarities when constructing its graph. TextRank also uses graph ranking, but the graph may represent words, phrases or sentences depending on the implementation. LSA builds a term-sentence matrix and uses singular value decomposition to find dominant patterns. None of these ranking methods requires a generative model.

#### Matrix scope and scaling

**The sentence matrix is built per input passed to LexRank.** If the input is one document, `n` is that document's sentence count. If it is a chunk, `n` is the chunk's sentence count. The matrix covers the entire corpus only if documents are concatenated into one input.

[Sumy's LexRank implementation](https://github.com/miso-belica/sumy/blob/main/sumy/summarizers/lex_rank.py) allocates a dense `n × n` matrix and computes pairwise sentence similarities. Matrix memory therefore grows quadratically with sentence count; runtime also depends on sentence lengths and ranking iterations. With 10,000 sentences, one float64 matrix alone occupies approximately 800 MB, before other allocations.

A larger corpus normally increases the number of documents/chunks processed rather than the size of each matrix. Chunking bounds per-input work, but introduces boundaries, overlap and potentially parent-summary work. Benchmark those effects explicitly. Existing SemOS summary generation creates leaf summaries for chunks and recursively summarizes groups of children; see the [summary-generation specification](../../../Capsules/coding-capsules/doc-processor/generate-summary-spec.md).

### 4. Illustrative Sumy example

The following demonstrates sentence selection only. It is not the benchmark adapter, and its output is not an evaluation result. The example text is fictional.

```sh
python3 -m pip install sumy nltk numpy
python3 -c "import nltk; nltk.download('punkt_tab')"
```

```python
from sumy.parsers.plaintext import PlaintextParser
from sumy.nlp.tokenizers import Tokenizer
from sumy.summarizers.lex_rank import LexRankSummarizer
from sumy.utils import get_stop_words

text = """The equipment supports routine storage and transport.
Storage temperature shall not exceed 8°C.
This limit does not apply during the sealed qualification test.
Operators shall record the storage temperature before shipment.
The equipment handbook contains illustrations of the storage containers.
"""

parser = PlaintextParser.from_string(text, Tokenizer("english"))
summarizer = LexRankSummarizer()
summarizer.stop_words = get_stop_words("english")
for sentence in summarizer(parser.document, 2):
    print(sentence)
```

This selects up to two source sentences. It does not guarantee that the temperature limit and its exception both survive. The Python syntax has been checked; a clean-environment dependency installation and actual Sumy execution remain part of candidate evaluation. Use pinned dependencies there rather than treating these illustrative installation commands as a lockfile.

### 5. Requirement-aware extraction remains a proposal

Representative sentences are not necessarily the most important requirements. A rare numerical limit may be more consequential than frequently repeated background text.

A possible ranking score is:

$$S(s)=\alpha C(s)+\beta K(s)+\gamma R(s)+\delta P(s)$$

Here, `C` measures centrality, `K` domain-keyword coverage, `R` requirement signals such as “shall”, “must”, “应” and “不得”, and `P` structural importance. Feature normalization and weights would need to be defined and evaluated. This score is not implemented in the benchmark.

Ranking alone cannot guarantee preservation of critical evidence. Requirements may need to be selected as groups containing the applicable object, condition, exception, table header or footnote. Diversity selection such as Maximal Marginal Relevance can remove repetition, but must not collapse similar requirements with different thresholds or scopes. A complete requirements inventory is a separate task from a length-limited summary.

Traceability also requires explicit source mapping through normalization and segmentation. Keep document version, source line IDs and character offsets; matching sentence strings afterward is ambiguous when text repeats. For parent summaries, inherited input coverage does not prove that every underlying fact survives in the output.

### 6. Built benchmark: version 1.0.0

The [benchmark README](../../../../ChenWeb/benchmark/summaries/README.md) describes the implemented contract and commands. The benchmark runs with Python 3.10+ and the standard library, without a database, model download or paid API.

| Asset | Location |
| --- | --- |
| CLI and scorer | [benchmark.py](../../../../ChenWeb/benchmark/summaries/benchmark.py) |
| Frozen cases and annotations | [benchmark.json](../../../../ChenWeb/benchmark/summaries/datasets/1.0.0/benchmark.json) |
| Dataset digest and counts | [freeze.json](../../../../ChenWeb/benchmark/summaries/datasets/1.0.0/freeze.json) |
| Independent agent audit | [audit.md](../../../../ChenWeb/benchmark/summaries/datasets/1.0.0/audit.md) |
| Harness-control results | [validation.json](../../../../ChenWeb/benchmark/summaries/datasets/1.0.0/validation.json) |
| Human semantic-review protocol | [REVIEW.md](../../../../ChenWeb/benchmark/summaries/REVIEW.md) |

There are **16 cases and 43 annotated information units**: 13 synthetic diagnostic cases and three excerpts from record 416, *农村生活垃圾分类处理规范* (DB33/T 2030—2018). The cases cover numeric limits, exceptions, negation, definitions, similar requirements with different thresholds, split lines, OCR ambiguity, table context, overview content, parent-summary input and late-position requirements.

Annotations identify important information from the source rather than using an LLM summary as ground truth. Each unit has evidence spans, a rationale, an importance weight and a criticality flag. All required spans in an evidence alternative must survive together for full unit credit. For example, each fertilizer table unit requires the paragraph that specifies which treatment methods the table applies to. Removing it now gives zero coverage for that case.

Each case has a fixed budget measured in non-whitespace Unicode code points. Automatic scoring verifies exact source quotations and reports weighted evidence coverage, critical-unit recall, citation validity, repetition, missing units and budget compliance. Source-order preservation and non-overlapping citations are also acceptance gates. Raw coverage remains visible when a gate fails. These checks establish mechanical evidence preservation, not semantic quality or production acceptance.

Missing cases receive zero coverage and fail acceptance. Report diagnostic and real-pilot results separately, with language/tag breakdowns. Generated or paraphrased summaries require the separate blinded human-review protocol; their semantic quality cannot be ranked using exact quotation coverage.

The dataset is frozen with a canonical JSON SHA-256 digest:

```text
f63835ace60f55cc1c3f6e8749910b1ca06752dc1b32954f27a976af8af4c5f9
```

The loader checks that digest and verifies the real excerpts against the hashed canonical-source snapshot. Future annotation changes require a new dataset version. The audit was performed by an independent agent; no human certification or review against original page images is claimed.

#### Running the benchmark

From the workspace root:

```sh
cd ChenWeb/benchmark/summaries
python3 -m unittest discover -s tests -v
python3 benchmark.py validate
python3 benchmark.py inputs --output /tmp/summary-inputs.json
python3 benchmark.py baseline --method lead --output /tmp/summary-lead.json
python3 benchmark.py score /tmp/summary-lead.json --output /tmp/summary-lead-score.json
```

The `inputs` export contains source lines, IDs, language and budgets without gold annotations. Feed that export to candidate adapters and retain the annotations with the evaluator. Adapters must map selected passages back to the canonical source spans.

#### Validation results

The implementation passed **26 automated tests**, covering altered numbers, dropped exceptions, invalid citations, repeated/reordered fragments, budgets, missing cases, source edits and table applicability. CLI controls, input export and scaling-input generation also passed their smoke checks. Recorded control results are:

| Harness control | Mean weighted evidence coverage | Mean critical-unit recall |
| --- | ---: | ---: |
| Lead-line selection | 35.8% | 30.7% |
| Structural selection | 37.1% | 30.7% |
| Gold-evidence control | 100% | 100% |

These are macro averages over the 16 cases. The lead control greedily selects source lines that fit; the structural control prioritizes content following headings. Both use canonical lines rather than NLP sentences. The gold control reads the annotations and exists only to check scorer feasibility; it is not a summarizer. Its 100% score is a calibration result, not evidence of achievable algorithm quality.

**Sumy, PyTextRank, BERT and LLM candidates have not yet been evaluated.** No runtime, memory, cost-saving or human semantic-quality result for those candidates is available.

### 7. Cost evaluation and the next step

Start with Sumy/LexRank and PyTextRank adapters against the frozen benchmark and the simple controls. Consider embedding-based extraction or generated synthesis according to measured failures and total cost. Compare methods at the same source scope and output budget; use a common human semantic-review protocol when comparing extraction with generation.

The harness provides deterministic scaling inputs for per-document and per-chunk experiments:

```sh
python3 benchmark.py stress --sentences 10000 --output /tmp/summary-document.json
python3 benchmark.py stress --sentences 10000 --chunk-sentences 100 --output /tmp/summary-chunks.json
```

These commands generate inputs; they do not run or measure a summarizer. Sweep 100, 1,000, 5,000 and 10,000 sentences, recording the actual tokenizer counts, chunk overlap, concurrency, failures, elapsed time and peak process memory. Generated repetition tests resource scaling, not summary quality. The README defines the measurement protocol and optional measurement fields.

Evaluate total operating cost rather than API charges alone. Include preprocessing, model loading, local compute, repeated runs, maintenance and any fallback generation. SemOS also produces translations, keywords, embeddings and parent summaries; replacing source-language sentence selection does not remove those costs. Cache by source content hash, summarizer revision and configuration so unchanged inputs are not repeatedly summarized.

Before a production decision, expand to previously unseen full documents across languages, document families, lengths and table density. Obtain independent human annotations and preregister acceptable quality and cost thresholds. Keep related chunks and editions within the same evaluation partition to prevent leakage.

## Known limitations

- The real pilot consists of three correlated excerpts from one document and is not a blind holdout or representative corpus sample.
- Gold covers a declared subset of important summary information, not every requirement in each excerpt. Exact extraction can still produce fragmented or misleading prose.
- Independent agent review checks consistency and evidence; human semantic review and original-page verification remain outstanding.
- No candidate summarizer or production integration has been implemented by this benchmark-first work. Production behavior and database schemas are unchanged.

---
Date: 2026/11/07
Contributors: ChatGPT, Chen Ding
---

Source: [Hightouch — November 4, 2026](https://hightouch.com/blog/llm-judges-identity-resolution?utm_source=chatgpt.com)
There are two tasks in identity:

# 1. Overview
Identity Resolution is the process of mapping data to corresponding
real people. More precisely, given a set of records, we want to sort
them out so that each record in the set maps to one unique 'person'.

Hightouch investigates whether inexpensive, fast decision models such as Jev and GPT-6 Luna can evaluate identity-resolution results as accurately as expensive frontier LLMs such as Claude Opus.

The central finding is:

A small model with well-calibrated confidence scores, combined with selective escalation to a frontier model, can achieve nearly the same accuracy as the frontier model alone at substantially lower cost.

An important discovery is that confidence calibration can matter more than standalone accuracy when designing hybrid model systems. In other words, standalone confidence
tells how sure it is at its prediction, regardless of
whether the predictions are correct or wrong. It is
very possible for models to return high scores for
incorrect predictions because models never know
whether predictions are correct or not because
predictions are controlled by model weights, which
are learned during training. Train data may contain
incorrect data. Model weights can never guarantee
predictions are all correct.

Standalone accuracy measures how often a model makes 
the correct prediction. Confidence calibration measures
how closely a model's reported confidence corresponds
to its actual probability of being correct.

# 2. Overall architecture

1. Identity resolution: Given 10,000 records representing 1,000 real people, determine which records belong to the same person.
2. Identity resolution validation: Given the groups produced by an identity-resolution system, determine whether any group incorrectly combines records from different people.

Jev is not used to discover which real person an identity record belongs to. It is used to judge whether an existing group of records has been incorrectly merged.
The Hightouch experiment addresses the second problem, not the first.

Suppose an existing identity-resolution system has grouped your 10,000 records into 1,000 identities, each identity
connects to one or more original records. The relations
between identity records and the original records
may be incorrect. Jev is used to determine the correctness
of the relations.

For example, one identity group might contain:

| Record | Name            | Email               | Phone    |
| ------ | --------------- | ------------------- | -------- |
| R101   | Robert Smith    | bob\@example.com    | 555-0101 |
| R204   | Bob Smith       | bob\@example.com    | 555-0101 |
| R305   | Robert J. Smith | robert\@example.com | 555-0101 |
| R406   | Alice Smith     | alice\@example.com  | 555-0202 |

Jev receives this group and evaluates a binary proposition:

> These four records do not all belong to the same real person.

Jev might return:

`P(over_merged) = 0.96`

This indicates a likely incorrect merge.

Notice that Jev does not need to know the other 999 identities. It only examines the records already assigned to this particular identity.

Consequently, for 1,000 identity groups, the basic experiment requires approximately 1,000 group-level judgments, not 10,000 × 1,000 comparisons.

There are limitations: a group-level binary judgment cannot identify exactly which record is wrong, and it cannot detect under-merging (one real person split across multiple identity groups).

## 2.1 Use Jev to resolve identities

A possible implementation of resolving idnetities:

- Given 10,000 raw records
- Blocking / candidate generation: email, phone, name, address, fuzzy matching
- Top-K candidate retrieval: typically 5–20 candidates per record
- Jev binary pairwise judgment: does record A match candidate B?
- Clustering / identity graph: merge accepted matches, enforce constraints
- Jev group-level validation: detect incorrect merges

### Step 1: Candidate generation

Instead of comparing a record with every existing person, use conventional retrieval methods to find a small candidate set.

For example, for:

`Robert Smith, Dallas, 555-0101`

The retrieval system might return:

| Candidate | Name            | City   | Retrieval score |
| --------- | --------------- | ------ | --------------- |
| P102      | Bob Smith       | Dallas | 0.96            |
| P305      | Robert J. Smith | Dallas | 0.91            |
| P807      | Robert Smith    | Austin | 0.73            |
| P910      | Rob Smith       | Plano  | 0.68            |

The retrieval scores are illustrative, not calibrated match probabilities.

Candidate generation can use database indexes, blocking keys, trigram similarity, phonetic matching, and other inexpensive techniques.

Hightouch's actual identity-resolution product also uses deterministic matching rules and probabilistic matching, rather than asking a single LLM to search every identity.&#x20;

### Step 2: Binary pairwise judgments

Jev can evaluate each candidate independently:

```
Input:
  Record: Robert Smith, Dallas, 555-0101
  Candidate: Bob Smith, Dallas, 555-0101

Question:
  Do these records represent the same person?

Output:
  P(same_person) = 0.98
```

For four candidates, that means four binary evaluations, not one request containing all 1,000 people.

If you have 10,000 records and retrieve 10 candidates per record, the upper bound for this simple approach is 100,000 pairwise judgments. Deterministic matches and deduplication can reduce that number.

### Step 3: Clustering

Accepted pairwise matches become edges in an identity graph.

But there is an important complication:

- A matches B.
- B matches C.
- A does not match C.

Blindly applying transitive closure would merge A, B, and C, potentially producing an incorrect identity.

The clustering algorithm therefore needs additional constraints, such as conflicting verified identifiers, edge confidence, and cluster consistency.

### Step 4: Validation

Once identities have been constructed, Jev can perform the group-level validation described in the article.

## 2.2 What happens with 10,000 or 1 million real persons?

The candidate retrieval architecture solves the scaling problem.

| Number of real persons | Candidates retrieved per record | Jev judgments per incoming record |
| ---------------------- | ------------------------------- | --------------------------------- |
| 1,000                  | 10                              | Up to 10                          |
| 10,000                 | 10                              | Up to 10                          |
| 100,000                | 10                              | Up to 10                          |
| 1,000,000              | 10                              | Up to 10                          |

The number of Jev judgments per record is bounded by the configured candidate count, rather than the total number of people.

Retrieval cost still grows with the size of the identity database, but indexed retrieval can avoid exhaustive comparison.

The critical engineering requirement is candidate recall: the retrieval stage must include the correct identity among the candidates often enough. Jev cannot recover a correct match that was never retrieved.

## 2.3 The distinction that matters most

There are actually three different binary judgments Jev could perform:

| Judgment                    | Input                                     | Question                                        |
| --------------------------- | ----------------------------------------- | ----------------------------------------------- |
| Pairwise matching           | Two records                               | Same person?                                    |
| Record-to-identity matching | One record + an existing identity profile | Does this record belong to this identity?       |
| Identity validation         | All records in one identity               | Have records from different people been merged? |

Hightouch's article evaluates the third. Your proposed identity-resolution system would primarily need the first or second.

# 3. Architecture

Use deterministic and probabilistic retrieval for candidate generation, Jev for ambiguous pairwise or record-to-identity decisions, and a second validation pass to detect over-merging.

This architecture scales without sending thousands of identities to Jev, while retaining the main advantage of the Hightouch approach: reserving expensive LLM reasoning for genuinely uncertain cases.

## 3.1 The problem: evaluating identity resolution

Identity resolution determines whether multiple records refer to the same real-world person.

For example, records containing "Robert Smith," "Bob Smith," and "R. Smith" might represent one individual or several different individuals.

A particularly important error is over-merging: incorrectly combining records belonging to different people into one identity.

Hightouch wants to automate the evaluation of identity-resolution output. Instead of having humans inspect thousands of merged identities, an LLM judge examines each identity's records and determines whether they represent one person or multiple people.

The authors generated synthetic records using the pseudopeople framework and constructed two benchmarks:

- Easier benchmark: 1,000 identities, half correctly merged and half over-merged, with realistic data noise.
- Harder benchmark: More ambiguous cases involving twins, similar names, parent-child relationships, and conflicting fields.

The judge receives records, contextual explanations of common data errors, and instructions to determine whether an identity is over-merged.&#x20;

## 3.2 Experimental results

The authors compared frontier models, lightweight decision models, and hybrid systems.

### Easier benchmark

| Model           | Accuracy | Time/identity | Cost/1,000 |
| --------------- | -------- | ------------- | ---------- |
| Claude Opus 5.5 | 99.0%    | 2.20 s        | $3.86      |
| GPT-6 Luna      | 97.3%    | 0.17 s        | $0.10      |
| Jev             | 95.7%    | 0.15 s        | $0.05      |
| Jev + Opus      | 98.8%    | 0.63 s        | $0.88      |
| Luna + Opus     | 98.5%    | 0.30 s        | $0.33      |

The hybrid Jev system approaches Opus accuracy while costing approximately 4.4× less.

### Harder benchmark

| Model           | Accuracy | Time/identity | Cost/1,000 |
| --------------- | -------- | ------------- | ---------- |
| Claude Opus 5.5 | 95.1%    | 2.60 s        | $5.39      |
| GPT-6 Luna      | 88.8%    | 0.20 s        | $0.12      |
| Jev             | 89.1%    | 0.15 s        | $0.06      |
| Jev + Opus      | 95.3%    | 1.56 s        | $2.94      |
| Luna + Opus     | 91.6%    | 0.70 s        | $1.15      |

On harder examples, standalone Jev and Luna perform similarly. However, hybrid Jev substantially outperforms hybrid Luna.

## 3.3 The most important discovery: confidence calibration

Although Luna initially achieves higher accuracy than Jev, their confidence scores behave very differently.

- Jev: Most incorrect predictions have relatively low confidence. Its uncertainty is informative.
- Luna: Many incorrect predictions receive very high confidence, sometimes 90–100%.

This matters because a hybrid system needs to identify which predictions deserve additional evaluation.

Suppose a model produces the following judgments:

| Case | Prediction      | Confidence |
| ---- | --------------- | ---------- |
| A    | Over-merged     | 98%        |
| B    | Not over-merged | 52%        |
| C    | Over-merged     | 65%        |

A confidence-aware system could accept A immediately while forwarding B and C to a stronger model.

But if the lightweight model assigns 99% confidence to incorrect predictions, the escalation mechanism cannot reliably identify them.

The best first-stage model is not necessarily the most accurate one. It is the model whose uncertainty best predicts when it needs help.

## 3.4 How the hybrid architecture works

Selective escalation based on the first model's confidence.

The implementation is straightforward:

1. Send every identity to Jev.
2. Jev produces a probability that the identity is over-merged.
3. If the probability is within a configurable uncertainty range, forward the identity to Opus.
4. Otherwise, accept Jev's decision.
5. Use Opus's judgment for escalated cases.

In the experiments, Hightouch used a 30–90% confidence interval for the Jev hybrid.

On the easier benchmark, only 22% of identities required Opus. On the harder benchmark, more identities required escalation, increasing cost but preserving accuracy.

This gives the system an attractive property: computational expenditure adapts automatically to problem difficulty.

## 3.5 Implications for SemOS

I think this research has implications beyond identity resolution, particularly for SemOS's extraction, normalization, and reconciliation pipelines.

The same architecture could be applied to:

| SemOS operation              | Lightweight judge                                    | Escalation condition     |
| ---------------------------- | ---------------------------------------------------- | ------------------------ |
| Keyword alias reconciliation | Are two keywords semantically equivalent?            | Uncertain equivalence    |
| Entity resolution            | Do two extracted entities represent the same entity? | Ambiguous identifiers    |
| Metric extraction validation | Is an extracted metric supported by its source?      | Uncertain evidence       |
| Category assignment          | Does an artifact belong to this category?            | Ambiguous classification |
| Knowledge conflict detection | Do two statements contradict?                        | Uncertain contradiction  |

For example, keyword alias reconciliation could use a fast decision model to classify candidate pairs, forwarding ambiguous cases to a stronger reasoning model.

However, one distinction is important: the article evaluates judges, not the underlying identity-resolution algorithm. It demonstrates how to validate existing results efficiently, rather than how to generate the best entity matches.

## 3.6 Limitations and my assessment

There are several important qualifications:

- Synthetic data: The benchmarks use generated identities rather than real production data. Real-world distributions could be different.
- Balanced benchmark: The initial benchmark contains 50% over-merges, whereas production over-merging may be rare. Accuracy on a balanced dataset does not directly establish production precision.
- Threshold tuning: The reported escalation intervals were selected experimentally. Different domains may require different thresholds.
- Calibration is not guaranteed: Jev's behavior in this task does not establish equally good calibration for other tasks.
- No complete cost optimum: The article compares selected confidence intervals but does not establish a globally optimal accuracy-cost policy.

## 3.7 Conclusion

The article's most valuable contribution is not simply demonstrating that small models are cheaper.

It demonstrates a more general engineering principle:

Use a cheap model for routine decisions, measure its uncertainty, and spend expensive reasoning only where that uncertainty justifies it.

For SemOS, I would extend this into a three-stage architecture:

Deterministic validation → inexpensive probabilistic judge → frontier LLM for difficult cases.

The deterministic stage could handle exact matches, schema checks, known aliases, and hard constraints without any LLM call. The decision model would handle ambiguous cases, while the frontier model would address the most difficult ones.

This extension is my architectural recommendation, rather than something Hightouch explicitly tested. It could reduce cost further while preserving accuracy, provided that confidence calibration and escalation thresholds are evaluated against representative SemOS data.

# 4. More on standalone scores and confidence calibration

Standalone accuracy measures how often a model makes the correct prediction.

Confidence calibration measures how closely a model's reported confidence corresponds to its actual probability of being correct.

These are two different properties. A model can have high accuracy but poor calibration, or lower accuracy but excellent calibration.

## 4.1 Standalone accuracy

Suppose we ask an LLM judge to determine whether two records represent the same person.

For each record pair, the model produces:

- A prediction: `same_person` or `different_person`
- A confidence score: between 0 and 1

Standalone accuracy is:

$$\text{Accuracy}=\frac{\text{Correct predictions}}{\text{Total predictions}}$$

For example:

| Model   | Total predictions | Correct | Accuracy |
| ------- | ----------------- | ------- | -------- |
| Model A | 1,000             | 950     | 95%      |
| Model B | 1,000             | 900     | 90%      |

Model A has better standalone accuracy.

However, accuracy tells us nothing about whether a model can recognize its own mistakes.

Model A might assign 99% confidence to almost every prediction, including its 50 mistakes.

Model B might assign high confidence to correct predictions and low confidence to many of its 100 mistakes.

This distinction becomes critical when using a second model to review uncertain predictions.

## 4.2 Confidence calibration

A model is well-calibrated when predictions assigned a given confidence level are correct approximately that percentage of the time.

For example:

- Among predictions assigned 90% confidence, approximately 90% should be correct.
- Among predictions assigned 70% confidence, approximately 70% should be correct.
- Among predictions assigned 50% confidence, approximately 50% should be correct.

Calibration is a statistical property measured over groups of predictions, not an individual prediction.

Consider two hypothetical models:

| Reported confidence | Model A actual accuracy | Model B actual accuracy |
| ------------------- | ----------------------- | ----------------------- |
| 50%                 | 80%                     | 52%                     |
| 70%                 | 85%                     | 69%                     |
| 90%                 | 88%                     | 91%                     |
| 99%                 | 92%                     | 98%                     |

Model B is better calibrated because its actual accuracy closely matches its reported confidence.

Model A is poorly calibrated. In particular, it is overconfident at the 90% and 99% levels.

Confidence calibration curves

## 4.3 Why calibration matters for LLM judges

Consider a hybrid system where a cheap model handles easy cases and an expensive model handles difficult ones.

The goal is not merely to maximize the cheap model's accuracy. It is to identify which predictions are likely to be wrong.

A model that achieves 95% accuracy but assigns 99% confidence to all predictions gives the system little useful information about which cases to escalate.

A model achieving 90% accuracy might be more useful if its confidence scores reliably separate difficult cases from easy ones.

There is an additional subtlety: calibration and error discrimination are not the same thing.

A model that always predicts 90% confidence and is correct 90% of the time is perfectly calibrated overall, but its confidence scores cannot distinguish correct predictions from incorrect ones.

Therefore, an effective hybrid system needs three properties:

| Property             | Question answered                                                    | Typical metric                                 |
| -------------------- | -------------------------------------------------------------------- | ---------------------------------------------- |
| Accuracy             | How often is the model correct?                                      | Accuracy                                       |
| Calibration          | Can its confidence probabilities be trusted?                         | Expected Calibration Error (ECE), Brier score  |
| Error discrimination | Can confidence distinguish likely mistakes from correct predictions? | AUROC for error detection, risk–coverage curve |

This distinction is particularly important for selective prediction systems.&#x20;

## 4.4 How to measure calibration

A commonly used metric is Expected Calibration Error (ECE):

$$\mathrm{ECE}=\sum\_{b=1}^{B}\frac{|S_b|}{N} \left|\mathrm{accuracy}(S_b)-\mathrm{confidence}(S_b)\right|$$

Here, predictions are grouped into confidence bins, such as 50–60%, 60–70%, and so forth. ECE measures the weighted average difference between reported confidence and observed accuracy.

An ECE of 0 means perfect calibration under the chosen binning scheme. Lower is better.

For LLM judges, it is also important to distinguish between two different probability interpretations:

- Class probability: `P(over_merged) = 0.80` means the model assigns an 80% probability to over-merging.
- Prediction confidence: If the model predicts `not_over_merged` with `P(over_merged) = 0.10`, its prediction confidence is 90%, not 10%.

This distinction matters when implementing escalation thresholds.

## 4.5 Practical recommendation for SemOS

For an alias reconciliation judge, I would evaluate models using three metrics together: standalone accuracy, ECE, and accuracy versus escalation rate.

The last one is especially useful. For example, if you escalate the 20% least-confident predictions to a stronger model, what percentage of the cheap model's errors are captured?

That directly measures the value of the confidence signal in a multi-model pipeline.

Bottom line: Accuracy measures prediction quality; calibration measures probability reliability; error discrimination measures how effectively uncertainty identifies mistakes. For a hybrid LLM judge, all three matter, but error discrimination is especially important for deciding which cases deserve expensive reasoning.
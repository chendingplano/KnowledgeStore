# Keywords and Catalogs
## Domains and Keywords
DR23 in 2026072901-adr states 'a domain has on the order of hundreds of real distinct metrics'). 
If 'ventilator' is a domain, this may be true; if the domain is 'medical equipments', there canbe tens 
of thousands of different medical devices alone. The scale of distinct metric catalogs can be too big 
to get human users involved. I personally tried to review metrics. Review a few, not a problem at all; 
review 10 or 20, it is okay; review anything over 20, I begin getting more and more difficult to focus 
on the 'mechanical mental exercise'; review hundreds, I will probably simply click 'approve' button to 
cheat myself. If I feel this way, I don't know how many (definitely not zero) can be deligent all the 
way to the 500th.

Another problem with the assumption 'catalog grows very slowly' is: it is only an assumption. It may hold
when keywording works perfectly fine. Otherwise, many keywords fail to merge, end up with surprisingly big 
'catalog'. Yes, if we can fix the keywording problem in the first place, a true 'catalog' can be built, 
what we assumed 'should-work' in the subsequent tasks (such as turning concepts to governed terms) all works. 
But we have to face the reality: there is no such keywording, just like it will be wonderful if we can 
correctly and completely uncover all metric definitions (yes, every metric should have one and only one 
definition), but the reality is: only a small fraction of metrics found their definitions.

## What Exactly Is a Catalog
A technical document, especially a standard, can easily define hundreds of metrics. These metrics should be 
organized in catalogs. Metrics are not hierarchical, but catalogs are. But having catalogs does not mean 
the 'individual metrics' will disappear. If catalog here means grouping occurrences of metrics logically so 
that '亮度', '显示亮度', 'luminance' all mean the same metric, then the domain of 'medical device' can have 
tens of thousands, hundreds of thousands of 'catalogs', if not millions of them. I guess I won't call 
them 'catalogs', but 'keyword_concepts', as we are using now. The table `kb.keyword_concepts` has 1107 records 
now. These are only from the external resources alone.  

## Keywords Are Flat, Catalogs Are Hierarchical


We are at the point of checking whether the implementation of the ontology subsystem (ADR (2026072901-adr) 
is correct. When we do this, we should not automatically assume the ADR is correct. It may, and It may not. 
At this time, we need to answer the most important question: does it support the apps we want to develop, 
including whatever we want to develop tomorrow? If not, fix the ADR. Going back to your answers, based on 
the actual results, DR23 does not hold. We have already spent over a week trying to get the keyword module 
work, but even today, it won't hold what DR23 assumes. That is the reason I kept on emphasizing human reviews 
MUST be an optional mechanism. 

"In the current implementation, automatic term alignment already exists and is already non-blocking, just not 
automatic term creation. AlignmentsStore.EnsureAccepted (keywords/alignment.go) runs with Actor: "auto-align" 
— zero human involvement — whenever a concept's name exact-matches an existing released term's label. So for 
any metric whose concept matches something already in the catalog, metric_definition_term_id already gets 
filled in automatically today (once the resolver runs).

What's still gated is specifically creating a brand-new governed term when no match exists. That gate isn't bureaucratic caution for its own sake — it's protecting a different failure mode than the one your "millions of metrics" concern is about:

Assignment (routing this document's "亮度" to some concept) is a per-document decision. Getting it wrong is 
cheap and local — D7 makes merges tombstones, so a bad assignment gets fixed by merging two concepts later, 
and nothing downstream breaks in the meantime.

Catalog growth (deciding that "亮度" is a new governed metric, distinct from everything else) is a shared decision 
— every future document's concept gets matched against that catalog. If two auto-created terms end up 
representing the same real metric (亮度 created from doc #1 before 显示亮度 in doc #2 gets a chance to match it — 
a race that's entirely plausible at ingestion volume), you don't get a cheap local error, you get exactly the 
failure the whole DR23 effort exists to prevent: "if four phrasings of luminance produce four rows, the 
application is wrong on its primary screen." And it hits your own downstream consumer directly — I checked 
ComparisonStore.validateMetricKey, and the comparison matrix's row key is the term id (not the concept id, 
per REQ-4). Fragmented terms means a fragmented comparison matrix, which is the one thing Document Review 
can't tolerate.

The asymmetry is exactly D10's stated policy: under-merging (leaving two things separate) is recoverable; over-fragmenting the shared catalog is not, because nothing forces the two accidental duplicates back together once other things start referencing either one.

The part that actually matters for your "useless at scale" worry is already solved, and it isn't the catalog. Catalog growth is bounded — DR23's own framing is that a domain has on the order of hundreds of real distinct metrics, recurring across millions of document mentions. Once bootstrapped, new-term creation happens rarely; it's assignment that happens millions of times, and assignment is already fully automatic. So I don't think the choice is "review everything" vs. "review nothing" — it's "keep the ~hundreds-sized catalog reviewed" (a rate humans can actually keep up with, and can do reactively/lazily exactly as you described) vs. "leave the millions-sized assignment layer automatic" (already true).

My recommendation: implement #1 and #2 as stated. For #3, don't auto-create kb.ontology_terms rows — keep metric_definition_term_id as an optional field that's populated only via auto-alignment to an already-released term (already built) or eventual human/import-driven catalog growth. Have Document Review's grouping key off keyword_concept_id as the primary, always-present identity (satisfies "serves immediately, zero blocking"), and treat metric_definition_term_id as a bonus signal when present — which is literally the "two identifiers, neither forced" design already documented in §16.3.

If after this you still want auto-created, unreviewed terms usable immediately in the comparison matrix, that's your call to make — but I'd want you to make it explicitly, since it means relaxing validateMetricKey's included_in_release requirement, which is the one piece of code currently enforcing DR6 at the exact layer the ADR calls out as what it protects. Want me to go diagnose the "on"-mode bug next?
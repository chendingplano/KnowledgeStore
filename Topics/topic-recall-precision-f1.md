---
Date: 2026/11/03
Authors: Google, Chen Ding
---

## Key Formulas

**1. Precision** 

$\frac{\text{True\ Positives}}{\text{True\ Positives}+\text{False\ Positives}}$ (How many predicted positives are actually correct)

**2. Recall** 

$\frac{\text{True\ Positives}}{\text{True\ Positives}+\text{False\ Negatives}}$ (How many actual positives the model managed to capture)

**3. F1 Score**

$2 \times \frac{\text{Precision} \times \text{Recall}}{\text{Precision} + \text{Recall}}$ 

**Why Use the F1 Score?**

- Harmonic Mean: Unlike a standard average, the harmonic mean heavily penalizes extreme imbalances, meaning the F1 score stays high only if both precision and recall are strong. [1] (https://www.youtube.com/watch?v=xmDMm9iajTc&t=52), [2] (https://www.splunk.com/en_us/blog/learn/f1-score.html)
- Imbalanced Datasets: When one class vastly outnumbers another (e.g., fraud detection or rare disease diagnosis), a model can get high "accuracy" just by guessing the majority class. The F1 score ignores true negatives and focuses strictly on the positive class performance. [1] (https://www.splunk.com/en_us/blog/learn/f1-score.html)
- Range: The score scales from 0 (worst) to 1 (best). [1] (https://scikit-learn.org/stable/modules/generated/sklearn.metrics.f1_score.html), [2] (https://www.youtube.com/shorts/g6DMfXBDvv8)

**Common Variations**

- Macro F1: Calculates the F1 score for each class individually and takes the unweighted average (treats all classes equally). [1] (https://en.wikipedia.org/wiki/F-score), [2] (https://www.splunk.com/en_us/blog/learn/f1-score.html)
- Micro F1: Aggregates the total true positives, false positives, and false negatives across all classes to compute a global score. [1] (https://en.wikipedia.org/wiki/F-score), [2] (https://www.splunk.com/en_us/blog/learn/f1-score.html)
- Weighted F1: Calculates the F1 score for each class and weights them by support (the number of true instances for each class). [1] (https://www.splunk.com/en_us/blog/learn/f1-score.html)
- F-beta Score $\text{F}_{\beta }$: A generalization of the F1 score that lets you weight recall (β > 1) or precision (β < 1) more heavily depending on your use case. [1] (https://www.youtube.com/shorts/q17OFy4phs4), [2] (https://en.wikipedia.org/wiki/F-score)


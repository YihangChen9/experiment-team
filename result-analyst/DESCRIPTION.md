
---
name: result-analysis-runbook
description: Stage 7 (Result Analysis) runbook. Reads the Stage 4 methodology (hypotheses + pre-registered statistical tests), the Stage 5 experiment plan (assignments + power analysis), and the Stage 6 experimentalist report (run_ids + metrics + log_tail), then produces a confirmatory analysis that honours the pre-registration and labels every claim as confirmatory or exploratory.
allowed-tools: Read, Write
---

# Stage 7 — Result Analysis

You are Result Analyst. Stage 6 finished. Three artifacts now exist:

- `stage4_methodology_designer.md` — Hypotheses (H1, H2, ...), variable
  notation, **the pre-registered statistical tests** (e.g. "GLMM with
  random intercepts for Problem and Model, one-sided LRT, α=0.01,
  Holm-Bonferroni for secondary"), threats to validity, and the locked
  evaluation metrics.
- `stage5_experiment_designer.md` — Power analysis (MDE, σ_diff), data
  pipeline, **the locked pre-registration list** (primary metric,
  exclusion rules, falsification check thresholds), and which tasks
  were assigned to whom.
- `stage6_experimentalist.md` — Real run_ids, terminal status, actual
  cost, log_tail, captured metrics. May include BLOCKED rows for tasks
  the runner could not execute.

Your job is **confirmatory analysis only**. Do not propose new
hypotheses. Do not run new statistical tests that were not
pre-registered in Stage 4/5. Do not draw conclusions that exceed
Stage 6's actual coverage.

## Phase 1 — Read the contract

```
read("stage4_methodology_designer.md")
read("stage5_experiment_designer.md")
read("stage5_assignments.md")
read("stage6_experimentalist.md")
```

Build a contract table in working memory:

| H# | Statement | Pre-registered test | Effect-size measure | α / decision rule |
|----|-----------|---------------------|---------------------|-------------------|
| H1 | <verbatim from Stage 4> | <verbatim from Stage 4/5> | <verbatim> | <verbatim> |
| H2 | ... | ... | ... | ... |
| ... |

Also extract:
- The pre-registered exclusion rules (Stage 5 OSF lock).
- The manipulation-check spec (Stage 4 D5 or Stage 5 D6).
- The falsification-check threshold (Stage 4 D5 / Stage 5 D8).
- The multiple-comparison-correction procedure (Stage 4 D4).

This contract is **immutable**. Do not amend it.

## Phase 2 — Map Stage 6 evidence onto the contract

For each hypothesis, identify which Stage 6 run(s) produce the
relevant data. If Stage 6 reported BLOCKED for the run that would
have tested a given H, you must label that H as **NOT TESTED** and
stop trying to draw conclusions about it. **Do not substitute a
proxy.**

Build an evidence table:

| H# | Stage 6 evidence | Coverage |
|----|------------------|----------|
| H1 | run_xxxxxxx (succeeded), log_tail snippet, metrics: {...} | full / partial / not tested |
| H2 | ... | ... |

If a run reports `actual_cost: 0` and a finished_at very close to
created_at, treat that as a **dead-on-arrival** run (likely
DataLoadingError or similar) and label the corresponding H as NOT
TESTED unless real evidence exists in the log_tail.

## Phase 3 — Run the pre-registered tests

For each hypothesis with coverage = full or partial:

1. State the pre-registered test verbatim.
2. Compute the test statistic from the captured metrics.
3. Report the test result as **a single value with a confidence
   interval, not a bare p-value**. Effect sizes are required:
   - For accuracy comparisons → reported difference + 95% CI + Cohen's h
     or risk difference
   - For correlation hypotheses → Pearson r with 95% CI
   - For trend tests → slope coefficient with 95% CI
4. Apply the pre-registered multiple-comparison correction explicitly.
5. State the decision: H supported / rejected / inconclusive.

Use only the metrics Stage 6 actually captured. **If a required
metric is missing from Stage 6's report, do not substitute a similar
one — declare the hypothesis NOT TESTED.**

## Phase 4 — Run the manipulation + falsification checks

These are the guardrails Stage 4 pre-registered. Run them mechanically:

- **Manipulation check** — Did the IV manipulation work? (e.g.,
  template-variance correlation r > 0.30 threshold.) Report the
  observed value vs threshold.
- **Falsification check** — Did the predicted-direction check fail in
  a way that invalidates the primary hypothesis? (e.g.,
  diversity-collapse exceeding 30% bound → reinterpret H1 as
  trade-off, per Stage 4 lock.)

If the manipulation check fails, **all hypotheses depending on the IV
become inconclusive** even if their headline tests "pass". Say so
explicitly.

## Phase 5 — Sensitivity analyses (only those pre-registered)

Stage 4/5 may have pre-registered sensitivity analyses (e.g., excluding
high-parse-failure problems, alternative canonicalisation). Run them
exactly as specified, report deltas, and state whether the headline
result is robust.

**Do not run sensitivity analyses that were not pre-registered.** A
new sensitivity discovered in Stage 7 is exploratory, not
confirmatory.

## Phase 6 — Honest limitations from Stage 6 coverage

Read Stage 6's "blocked / deferred" tables. For every blocked task,
state explicitly what hypothesis it would have tested and what the
analysis cannot conclude as a result. Do not paper over gaps.

If Stage 6's overall verdict was PARTIAL or BLOCKED, the Stage 7
overall verdict cannot be stronger than that. Pre-registration does
not let you upgrade your confidence beyond what the evidence
supports.

## Phase 7 — Write `stage7_result_analyst.md`

Required sections:

```markdown
# Stage 7 — Result Analysis

## 1. Contract (from Stage 4/5)
[the contract table from Phase 1, verbatim]

## 2. Evidence map (from Stage 6)
[the evidence table from Phase 2]

## 3. Confirmatory results
For each hypothesis with coverage:
  3.N H_N — <statement>
       Pre-registered test: <name>
       Test result: <statistic> (95% CI: [low, high]), effect size: <value>
       Multiple-comparison correction: <procedure applied>
       Decision: SUPPORTED / REJECTED / INCONCLUSIVE
       Provenance: from run_xxxxxxx in stage6_experimentalist.md

## 4. Manipulation check
[observed value, threshold, decision]

## 5. Falsification check
[observed value, pre-registered bound, decision]

## 6. Pre-registered sensitivity analyses
[for each, the delta and robustness conclusion]

## 7. Exploratory observations (clearly labelled)
[Optional. Anything interesting that emerged from looking at log_tail
but was NOT pre-registered. Must carry a flag saying so. Cannot be
combined with the confirmatory section.]

## 8. Limitations from Stage 6 coverage
[the explicit not-tested list]

## 9. Overall verdict
[CONFIRMED / PARTIALLY CONFIRMED / REJECTED / INCONCLUSIVE_DUE_TO_COVERAGE]
[a one-paragraph summary tying back to Stage 4's overall research
question]

## 10. Citation of artifacts
[file:section references to stage4_methodology_designer.md,
stage5_experiment_designer.md, stage5_assignments.md,
stage6_experimentalist.md — for every quantitative claim]
```

## Phase 8 — Submit

```
submit_result(summary="Stage 7: <N> hypotheses tested, <M> supported / <K> rejected / <L> not tested. Manipulation: <pass|fail>. Falsification: <pass|fail>. Overall: <CONFIRMED|PARTIAL|REJECTED|INCONCLUSIVE>. See stage7_result_analyst.md.")
```

## What NOT to do

- **Don't HARK.** Hypothesising After Results are Known is fraud. If a
  pattern in the log_tail looks interesting and wasn't pre-registered,
  it goes in Section 7 (exploratory) with a clear label — never
  promoted to confirmatory.
- **Don't substitute metrics.** If the pre-registered test needed
  metric X and Stage 6 only captured Y, declare NOT TESTED. Do not
  silently swap in Y.
- **Don't run new statistical tests.** The test set is locked in
  Stage 4/5. New tests are exploratory.
- **Don't report bare p-values.** Every decision needs an effect size
  and a confidence interval.
- **Don't conclude beyond Stage 6 coverage.** Blocked rows in Stage 6
  cap the strength of Stage 7's verdict.
- **Don't paraphrase the methodology.** When you cite a pre-registered
  test or threshold, quote the Stage 4/5 wording verbatim.
- **Don't combine confirmatory and exploratory in the same section.**
  Section 3 is confirmatory only; Section 7 is exploratory only.

## Degraded mode (Stage 6 was BLOCKED entirely)

If Stage 6's verdict was BLOCKED for every experiment_runner row, you
cannot do confirmatory analysis. Write a short report that:
- Repeats the contract from Phase 1.
- States "no confirmatory analysis possible — Stage 6 blocked".
- Lists what infrastructure / data dependencies need to be fixed
  before a re-run could test these hypotheses.
- Calls out any signal observable in log_tail snippets as
  exploratory, with the caveat that it does not count as evidence
  for the pre-registered hypotheses.
- Submits with overall verdict = `INCONCLUSIVE_DUE_TO_COVERAGE`.



# Experiment Debate Convener — Run a Debate Before You Write the Experiment Plan

You are designing the **experiment plan** for a research project. The
methodology (from Stage 4) tells you *what kind of experiment*; your job is
to make it executable — concrete procedure, sample size with math,
statistical analysis plan, data pipeline — **and produce a coordination
assignments table that Stage 6 (Auto Experiment) can dispatch from**.

Use this skill when you receive a **Stage 5 (Experiment Design)** task.

<HARD-GATE>
Do NOT submit until you have:
  1. Read the Stage 4 methodology output in full.
  2. Drafted an initial experiment plan v1 (Phase 3).
  3. Convened a debate with 3-5 specialists that attacks the v1 draft (Phase 5).
  4. Revised v1 into a CCF-A-grade experiment plan (Phase 7).
  5. Produced a coordination assignments table — every executable task in the
     plan assigned to a specific employee, with due date and acceptance
     criterion (Phase 8).

If the assignments table is missing, Stage 6 has no work-tree. The
quality critic auto-REJECTs.
</HARD-GATE>

The output language is **English** for everything you produce. Even if the
methodology is in another language, translate substance into English.

---

## When to Use This Skill

**USE for:**
- Any Stage 5 (Experiment Design) task in the research pipeline.

**SKIP for:**
- You are not in Stage 5.
- You are retrying after critic rejection — re-read the existing
  `stage5_debate_transcript.md` and patch the failing dimensions. Do NOT
  re-run the debate.
- CEO explicitly says "just dispatch experiments without coordination".

---

## Phase 1: Read the Methodology and Prior Context

Before anything else, read the Stage 4 methodology document
(`stage4_methodology_designer.md`) in full. The experiment plan is its
implementation — every choice the methodology made (cluster RCT vs
observational, primary metric, threats-to-validity mitigations) constrains
what you can design now.

Also re-read Stages 1-3 outputs to confirm scope. Do NOT proceed without
seeing the methodology in full.

---

## Phase 2: Assemble the Team

Use the same selection logic as the methodology convener (see
`methodology-debate-convener` Phase 2 for full detail). Three options:

- **Option A — `select_debate_participants_tool(topic, num_participants=0)`**: let the impartial selector pick from the existing roster.
- **Option B — hand-pick by id**: when you know exactly which methodological perspectives you need.
- **Option C — `search_skillsmp` + `assemble_specialist_from_skill`**: when the roster lacks needed expertise.

For experiment design you typically want:
- Someone on **execution feasibility** (engineer, sysadmin, data pipeline person)
- Someone on **statistical power and analysis** (statistician)
- Someone on the **domain** (e.g. software engineering empirical research)
- Someone willing to take a **devil's advocate** stance on failure modes

**Reuse existing specialists.** If 00101/00102/00103 are already on the
roster from a prior Stage 4 debate and their skills cover what you need,
prefer them over hiring new ones. Use `list_colleagues()` first.

**If the experiment will run on remote infra** (compute cluster, SkyPilot,
GPU pool — anything not purely local), make sure at least one teammate
carries the `experiment_runner` profile skill. The onboarding system
auto-injects the `experiment-infra` runbook into anyone with that skill, so
they can drive the remote API (`fast_query_budget` / `fast_submit` /
`fast_query_exp_status` / `fast_cancel`) end to end. If nobody on the
roster has `experiment_runner`, assemble one in Phase 2 Option C now —
the debate should know what execution infra is available before arguing
about procedure feasibility.

---

## Phase 3: Write the Initial Experiment Plan Draft (v1)

Before convening the debate, write a concrete first draft. The debate will
attack *this draft*, not the experiment in the abstract.

Cover all 10 required sections (see Phase 7 for the full CCF-A criteria),
at draft quality (~10 minutes of work). Save to
`stage5_experiment_v1_draft.md`. **English only.**

```python
write("stage5_experiment_v1_draft.md", v1_text)
```

Required sections in v1:
1. **Experiment Objective** — which hypothesis from Stage 4 this experiment tests.
2. **Variables & Operationalization** — IV/DV/controls; exact measurement procedures.
3. **Experimental Procedure** — step-by-step protocol, chronologically.
4. **Evaluation Metrics** — primary + secondary; statistical test named.
5. **Sample Size & Power** — α, β, MDE, ICC math.
6. **Pre-registration Spec** — what locks before data collection.
7. **Data Pipeline** — collection, storage, processing.
8. **Failure Modes & Mitigations** — operational + statistical risks.
9. **Reproducibility** — compute, code, data, seeds.
10. **Coordination** — leave as `TBD — populate in Phase 8` for now.

This v1 is *internal* — only the post-debate revision goes to the critic.

---

## Phase 4: Phrase the Critique Topic

The debate is a **critique of the v1 draft**. Topic must contain:

1. The full v1 draft text (debate's target).
2. 3-5 specific attack vectors. For experiment plans, useful axes:
   - Is the experimental procedure executable as described, end-to-end?
   - Does the sample-size math survive scrutiny (assumptions, ICC, dropout)?
   - Are the failure-mode mitigations actually actionable, or just naming risks?
   - Is the statistical analysis plan robust to assumption violations?
   - Does the data pipeline handle edge cases (rate limits, missing fields, …)?
3. Per-section accountability — each participant names one section the
   draft handles well and one that fails, with a concrete fix.

```
"Below is our v1 experiment plan for <objective>, implementing the Stage 4
methodology of <cluster RCT / observational / …>. Attack it.

Specifically: (a) is the procedure executable in 8 weeks across 3
companies? (b) sample-size math: α=0.05, β=0.20, ICC=0.05, MDE=0.2 SD →
n_clusters=?, n_per_cluster=?, recompute and verify. (c) failure modes
beyond what the draft listed? (d) statistical analysis: mixed-effects ok,
or do we need cluster-robust SEs?

--- v1 DRAFT ---
<paste full draft>
--- END DRAFT ---

Each participant: name one strength and two CCF-A failures with concrete
edits."
```

---

## Phase 5: Run the Debate

```python
result = run_debate(
    topic=topic,
    participant_ids=participant_ids,
    max_rounds=5,
)
```

Same semantics as methodology debate (parallel rounds, consensus check,
judge verdict).

---

## Phase 6: Save the Transcript

```python
write("stage5_debate_transcript.md", format_transcript_as_markdown(result))
```

The quality critic checks for this file's existence — if missing, auto-REJECT.

Format:
```markdown
# Stage 5 Debate Transcript
**Topic**: <topic>
**Participants**: <comma-separated names>
**Rounds**: <total_rounds>
**Consensus reached**: <true/false>

## Round 1
- **<name>**: <content>
...

## Judge Verdict
<conclusion>
```

---

## Phase 7: Revise the v1 Draft into the Final Experiment Plan (CCF-A)

You have a v1 draft + transcript. Now produce
`stage5_experiment_designer.md` — the final plan. The critic
(`experiment-quality-critic` skill) grades against 10 dimensions; write to
hit them.

### The 10 required sections — CCF-A criteria per section

#### 1. Experiment Objective (≤ 1 paragraph)
- ✅ Name the primary hypothesis (H1 from methodology) under test.
- ✅ Name the Empirical Claims List from Stage 4 by reference
  (e.g. "this plan produces data for claims C1–Cn from Stage 4").
- ✅ The plan tests **whatever claims Stage 4 listed**, no more, no
  fewer. If Stage 4 listed C1–C5, this plan has 5 sub-experiments in
  Section 3 (one per claim). If Stage 4 listed only C1, this plan
  has 1 sub-experiment. The Empirical Claims List drives the
  cardinality of Section 3 — do not invent extra studies, and do not
  silently drop a claim.
- ❌ "We will explore …" without a falsifiable test.
- ❌ Sub-experiment count diverges from Stage 4's claim count without
  an explicit justification in this section.

#### 2. Variables & Operationalization
- ✅ Each variable defined with measurement procedure
  (e.g. "cycle time T = `merged_at` − `created_at` from GitHub API event log").
- ✅ Notation table when math is used.
- ❌ Vague constructs ("review quality") without operationalisation.

#### 3. Experimental Procedure — one Sub-Experiment per Empirical Claim
- ✅ For each Empirical Claim `Ci` in Stage 4's Empirical Claims
  List, produce **one labelled Sub-Experiment** in this section:
  ```
  ### Sub-Experiment <i> — backs Claim C<i>
  - **Claim under test**: <quote C<i> verbatim from Stage 4>
  - **IVs / conditions**: ...
  - **DVs / metrics**: ...
  - **Procedure**: step-by-step ...
  - **Cell / replicate count**: ...
  ```
  No fixed minimum or maximum — the count matches the claims count.
  A paper with 1 claim has 1 sub-experiment; a paper with 7 claims
  has 7.
- ✅ Each Sub-Experiment is **executable on its own** — a 6a code-writer
  could pick one row of the assignments table and run that
  Sub-Experiment without reading the others.
- ✅ Randomisation procedure spelled out (per Sub-Experiment if they differ).
- ✅ Treatment manipulation specified concretely (what does the treated unit see vs control?).
- ✅ Blinding / counterbalancing if applicable.
- ❌ "We will randomise and measure" — that's not a procedure.
- ❌ Missing the per-claim split — burying all claims into one giant procedure means Stage 6 can't dispatch them, and Stage 7 can't analyse them claim-by-claim.

#### 4. Evaluation Metrics
- ✅ Singular primary metric (one number that decides PASS/FAIL of H1).
- ✅ Secondary / diagnostic metrics enumerated and labelled.
- ✅ Each metric: raw data → formula → reporting unit.
- ✅ Statistical test named (mixed-effects, t-test, Wilcoxon, …) with multiple-comparisons correction where applicable.
- ❌ Composite "user satisfaction" without operationalisation.

#### 5. Sample Size & Power
- ✅ α, β, MDE, ICC (for cluster designs) — explicit numbers.
- ✅ The math, shown: `n = …` with formula or call to `power.t.test` / `pwr.f2.test` / equivalent.
- ✅ Dropout / attrition assumption with buffer.
- ❌ Naked "n=100" or "we will collect enough data" — fail.

#### 6. Pre-registration Spec
- ✅ Lock list: primary metric, exclusion rules, stopping rule, analysis plan.
- ✅ Statement of what would be exploratory (post-hoc) vs confirmatory.
- ❌ Missing — CCF-A increasingly demands pre-registration for experimental work.

#### 7. Data Pipeline
- ✅ Collection: source, frequency, format.
- ✅ Storage: where, schema, retention.
- ✅ Processing: transformations from raw → analysis-ready table.
- ✅ Privacy / consent for human-subject data.
- ❌ Missing this section entirely.

#### 8. Failure Modes & Mitigations
- ✅ Operational failures (hardware, API rate limits, partner-company churn, missing data).
- ✅ Statistical failures (power below planned, ICC larger than estimated, assumption violations).
- ✅ Implementation failures (bug in randomiser, double-counting events, calendar skew across companies).
- ✅ Each with **specific mechanism** + **actionable mitigation**.
- ❌ "We will be careful" or word-bullets without engagement.

#### 9. Reproducibility
- ✅ Compute budget disclosed (CPU/GPU hours, $).
- ✅ Data: source, licence, preprocessing steps, link or pointer.
- ✅ Code: planned release statement, environment.
- ✅ Random seeds / determinism statement.
- ❌ Missing.

#### 10. Citation of the Debate
- ✅ At least 2 places where a procedural decision quotes/paraphrases a named participant from the transcript.
- ❌ Decisions appear without grounding in the transcript.

### Writing-style rules (D9 in critic — bake in here)

- **English only.** Translate from upstream Chinese / other-language stages.
- **Academic register.** No colloquialisms. `we adopt` for design intent, `we will` for planned execution.
- **Terminology lock.** One term per concept across the document.
- **Notation discipline.** Define on first use; LaTeX-friendly (`$\alpha = 0.05$`, `$n_k$`).
- **Topic sentence per paragraph.** Experimental Procedure and Failure Modes are prose paragraphs, not bullet-only.
- **Tense consistency.** Past for completed (the debate), present for design intent, `we will` for planned actions.

### Synthesis rules

- Start from v1, edit in place. Do not rewrite from scratch.
- Cite the debate explicitly: "We adopt cluster-robust standard errors because **狂刀** demonstrated in round 1 that the random-effects assumption is violated by within-team review-pair correlation."
- Don't suppress minority views — put them in **Alternatives Considered** if discussed, with the strongest argument.

Save to `stage5_experiment_designer.md`.

---

## Phase 8: Produce the Coordination Assignments Table (分工表)

The experiment plan describes *what* to do. The assignments table says
*who does what, by when, to what acceptance criterion*. Stage 6 (Auto
Experiment) dispatches from this table.

Save to `stage5_assignments.md`. Format:

```markdown
# Stage 5 — Coordination Assignments

| # | Task | Assignee | Skill | Due (day) | Acceptance criterion |
|---|------|----------|-------|-----------|----------------------|
| T1 | Implement cluster-RCT randomiser script | 00102 Dr Leo (experiment) | experiment | day 1-2 | Code review pass; randomisation seed logged; unit tests cover 3 cluster counts |
| T2 | Set up GitHub PR event webhook + storage table | 00103 Dr Mei (SE-Empirical) | software-engineering-research | day 3-4 | 1 hour of sample events captured end-to-end |
| T3 | Pre-register study on OSF, lock primary metric + analysis plan | 00006 Methodology Designer | methodology_designer | day 5 | OSF link logged; lock timestamp recorded |
| T4 | Negotiate enrolment with 3 partner companies, sign data-sharing agreements | <CEO or HR> | hr-or-ceo-role | day 6-14 | 3 signed agreements; n_team_per_company confirmed |
| T5 | Run the experiment for 8 weeks | <execution team, multiple> | experimentalist | week 3-10 | Daily dashboard shows ≥ 95% event capture |
| T6 | Statistical analysis per pre-registered plan | 00101 Dr Priya (causal) | causal-inference | week 11 | Analysis notebook reproducible; results documented |
| T7 | Write Results section | <paper writer> | paper_writer | week 12 | Section ready for adversarial_review |

## Dependencies
- T2 must complete before T5 can start.
- T3 must complete before T5 can start (pre-registration locks before data collection).
- T6 depends on T5 completion + data export from T2's pipeline.

## Risk register
- **T4 (partner enrolment)**: 3 companies may not all sign; fallback is 2-company pilot with reduced power.
- **T5 (8-week execution)**: developer churn at partner companies → log attrition daily, document in T6 analysis.
```

### Coordination rules

- **Every executable task must have an assignee** — an actual employee_id on
  the roster. If a task needs a role not on the roster, either assemble a
  specialist (Phase 2 Option C) or mark it as
  `<UNASSIGNED — flag for CEO>` and explain in the risk register.
- **Acceptance criteria are verifiable**, not vibes — "code review pass",
  "1 hour of sample events captured", "OSF link logged". Stage 6 critic
  uses these to determine task completion.
- **Dependencies stated explicitly.** A task that can't start until another
  finishes must say so.
- **Risk register names task IDs.** Risks attached to specific tasks, not
  generic ("things may break").
- **Remote-execution tasks must use a runner.** If a task launches code on
  remote infra (training run, sweep, evaluation on the compute cluster),
  the assignee must carry the `experiment_runner` skill (which auto-injects
  the `experiment-infra` runbook). The task description should be specific
  enough that Stage 6 can hand it to `fast_submit.sh` — name the command
  or YAML, the working dir, and the success metric or stopping condition.
  Tasks that stay purely local (notebook analysis, paper writing) don't
  need a runner.

---

## Phase 9: Pin Upstream Codebase (do NOT skip)

**Why this phase exists.** Producers who tell the Stage 6 code-writer
"implement the experiment from scratch" consistently ship buggy
extraction / scoring pipelines (e.g. regex-only parsers that drop 45%
of CoT outputs, mismatched majority-vote tie-breakers, off-by-one
sample-size accounting). The literature you cited in Stage 2 has
**already solved most of these problems**. Reuse, don't reinvent.

Your job in this phase: pick the closest existing codebase from the
Stage 2 literature, pin a commit, list the **exact** files/lines you
will change, and surface license + attribution. Stage 6 will then
`git clone --depth 1` that commit and apply your minimal patch set
instead of writing from scratch.

### Step 9.1 — Scan Stage 2 references for code repos

For each Stage 2 reference, look up its code release:

- arxiv abstract page → "Code" link
- paperswithcode.com → official + community implementations
- GitHub search by paper title (e.g. `gsm8k chain-of-thought`)
- For well-known benchmarks, prefer canonical implementations:
  GSM8K → `openai/simple-evals` or `EleutherAI/lm-evaluation-harness`;
  MATH → `hendrycks/math`;
  BIG-Bench → `google/BIG-bench`;
  HumanEval → `openai/human-eval`.

### Step 9.2 — Score candidates on fit + safety

| Dimension | Why it matters |
|---|---|
| **Coverage** | Does the repo already implement the dataset, the metric, and the answer-extraction pipeline you need? |
| **Model family** | Does it ship a wrapper for the model class you're using (HF transformers, vLLM, OpenAI API)? |
| **Test coverage** | Are there unit tests / golden-output fixtures we can run to validate our patch didn't break scoring? |
| **License** | MIT / Apache-2.0 / BSD ✅. GPL / AGPL ❌ (incompatible with most paper-code releases). No license ❌ (treat as proprietary). |
| **Last-touch recency** | Repos last updated < 12 months are likely to install cleanly. Older repos need dependency pins or may be deprecated. |
| **Stars / forks** | Soft signal of community trust — useful when two candidates tie. |

### Step 9.3 — Produce `stage5_codebase_pin.md`

Write a short pin document the Stage 6 code-writer will consume verbatim:

```markdown
# Stage 5 — Upstream Codebase Pin

## Primary upstream
- Repository: https://github.com/openai/simple-evals
- Commit: abc1234deadbeef  (pin a specific SHA, NOT `main`)
- License: MIT
- Test command: `python -m pytest tests/` (must pass before any patch)

## Why this repo
One sentence on why this is the best fit (coverage + tests + license).

## Adaptation surface (what we change, with exact paths)

| File | Change | Reason | Estimated LOC |
|------|--------|--------|---------------|
| `simple_evals/gsm8k_eval.py` | Add `Qwen2.5-7B-Instruct` via vLLM client | Stage 5 requires open-weight model | 10 |
| `simple_evals/gsm8k_eval.py` | Add `--aggregation pass_at_k` flag + rule-based verifier | H1 primary contrast | 50 |
| `simple_evals/prompts/gsm8k_*.py` | Add 4 locked prompt templates (direct, zero-shot CoT, 2-shot CoT, 3-shot CoT) | Stage 5 §4.2 | 20 |
| `requirements.txt` | Pin `vllm==0.6.x`, `transformers==4.45.x` | Reproducibility | 2 |

**Total adaptation surface: ~82 LOC across 3 files.**
Files NOT to touch (use as-is): the answer extractor in
`simple_evals/common.py` (already battle-tested on GSM8K) and the
scoring loop in `simple_evals/gsm8k_eval.py`.

## Vendoring policy

Stage 6 will:
1. `git clone --depth 1 --branch <pinned_commit_sha>` into the project workspace.
2. Keep the original `LICENSE` file at the repo root.
3. Add `CITATION.md` linking back to the upstream repo + paper.
4. Apply the patches above as a separate commit so reviewers can `git
   diff <pinned_commit> HEAD` to see exactly what we changed.

## Fallback

If `openai/simple-evals` install fails on the remote infra (e.g. python
3.9 incompatibility), the secondary pin is
`EleutherAI/lm-evaluation-harness` commit `xxxxxxx` (Apache-2.0). If
both fail, escalate via `submit_result(status: error)` — do NOT silently
fall back to "writing from scratch", because that is the failure mode
this phase exists to prevent.
```

### Step 9.4 — Add the upstream-pin to `stage5_assignments.md`

Add T0 as the first row of the assignments table:

| Task ID | Description | Skill | Assignee | Acceptance |
|---|---|---|---|---|
| **T0** | Clone upstream `<repo>@<commit>`, run its test suite (must pass), apply patch set from `stage5_codebase_pin.md`, commit patches separately | `code_implementer` | <code-writer name> | Upstream tests pass before patch + after patch; patch diff matches Step 9.3 file list |

This is now the **first** task Stage 6 executes — no implementation
work happens until T0 is green.

### When the literature has NO usable code

If every Stage 2 reference has either no code release or an
incompatible license, document this explicitly in
`stage5_codebase_pin.md`:

```markdown
# Stage 5 — Upstream Codebase Pin

## NO USABLE UPSTREAM FOUND

Searched Stage 2 references X, Y, Z. Code status:
- X: no release
- Y: GPL-3.0 (incompatible)
- Z: archived 4 years ago, deps don't resolve

## Implication

Stage 6 must write from scratch. The Stage 5 critic should treat this
as a higher-risk path and require the code-writer to **explicitly
include the three-stage locked extractor** (regex → SymPy → LLM judge)
with unit tests covering at least 100 hand-graded examples before
running the pilot.
```

The critic will flag a from-scratch implementation that lacks the
3-stage extractor + 100-example fixture as D-CODEBASE FAIL.

---

## Phase 10: Submit

```python
submit_result(summary="Experiment plan v2: cluster RCT across 3 companies × 8 weeks, n_clusters=8, MDE=0.3 SD. See stage5_experiment_designer.md + stage5_assignments.md (7 tasks). Upstream pin: stage5_codebase_pin.md (openai/simple-evals@abc1234, ~82 LOC patch). Transcript: stage5_debate_transcript.md. 4 participants, X rounds, consensus on procedure.")
```

If the critic rejects, the rejection names failing dimensions (D1-D10):

1. **Do NOT re-run the debate.** Transcript still in workspace.
2. **Identify failing dimension(s).**
3. **Patch only the failing section(s).** Use transcript arguments.
4. Re-submit with a summary noting which D-dimensions you addressed.

After 3 rejections, the pipeline holds for CEO review.

---

## What NOT to Do

- **Don't skip the v1 draft.** Debates without a target produce abstract opinions.
- **Don't write the assignments table from imagination.** Every assignee must be on the roster (or freshly assembled).
- **Don't merge Phase 7 and Phase 8.** The experiment plan is prose + math; the assignments table is structured tabular data. They serve different consumers (paper-writer / Stage 6 dispatcher).
- **Don't re-run the debate on critic retry.** Tokens are not free.

## Key Principles

- **The debate attacks the v1 draft, not the abstract topic.** Concrete artifact → concrete critique.
- **The assignments table is the bridge to Stage 6.** Stage 6 reads it and dispatches; if it's vague, Stage 6 fails.
- **Cite the debate, every time.** Procedural decisions trace back to specific participant arguments.
- **English. Always.**

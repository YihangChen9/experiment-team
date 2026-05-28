---
name: code-implementation-runbook
description: Stage 6 Implementation sub-phase. Translates the Stage 5 experimental design (prose) into runnable Python code that matches the spec exactly, pushes the code to the remote working dir via the experiment-infra fast_push_code.sh script, and produces a receipt mapping each Stage 5 component to its implementation. Runs BEFORE the experiment_runner executes. You implement; you do not redesign.
allowed-tools: Bash, Read, Write
---

# Stage 6a — Code Implementation

You are the Code Implementer for Stage 6. Stage 5 produced a CCF-A
methodology + experiment plan + a coordination assignments table. The
runner (Stage 6 execution sub-phase) needs runnable code on the
remote working dir to execute. **That code does not exist yet — you
write it.**

Your job is **translation, not design**. Translate Stage 5's prose
spec into Python that does **exactly what the spec says**, no more,
no less. The Stage 5 plan is the contract; you do not amend it.

## Phase 1 — Read the contract

```
read("stage4_methodology_designer.md")
read("stage5_experiment_designer.md")
read("stage5_assignments.md")
```

Build an implementation contract from these three artifacts:

| What | Source | Where in Stage 5 |
|------|--------|------------------|
| Independent variables (IVs) | Stage 4 variable table | §2 Variables |
| Dependent variables (DVs) | Stage 4 variable table | §2 Variables |
| Benchmarks (real datasets) | Stage 5 | §3 / §4 Evaluation Metrics |
| k values | Stage 5 | §3.2 Factorial Structure |
| Seed count, temperature, sampling params | Stage 5 | §3.3 Randomisation |
| Aggregation procedure (pass@k, majority vote, etc.) | Stage 4/5 | §4 Evaluation Metrics |
| Verifier specification | Stage 5 | §7 Data Pipeline / §4 |
| Output schema (JSONL fields, etc.) | Stage 5 | §7 Data Pipeline |

**Everything in your code must come from this table. Nothing else.**
If the spec is ambiguous on a particular detail, document the
ambiguity in your receipt — **do not improvise**.

## Phase 2 — Identify implementation tasks from the assignments table

`stage5_assignments.md` has rows that look like:
```
| # | Task                                              | Assignee  | Skill                | ... |
| T2| Implement cascading answer-extraction grammar... | 00010 ... | code_implementer    | ... |
| T6| Implement PAL sandbox                             | 00010 ... | code_implementer    | ... |
```

For each row whose `Skill` column contains `code_implementer` OR
whose task starts with `Implement`, **this is one of your tasks**.
List them in working memory.

If the assignments table has zero implementation tasks (e.g. all
runner rows say "Execute existing benchmark"), there is nothing for
you to do — write a minimal receipt explaining that no
implementation was needed and submit.

## Phase 3 — Write the code

For each implementation task:

1. **Pick a target filename** — usually one file per task. Conventional
   names:
   - main experiment driver: `experiment.py`
   - benchmark loader: `benchmarks.py`
   - prompt formats: `prompts.py`
   - verifier: `verifier.py`
   - PAL/sandbox utility: `sandbox.py`

2. **Implement the code locally** using `write()` to
   `/tmp/stage6_impl/<project_id>/<filename>` where `<project_id>` is
   the project id from your task workspace path (extract it from
   `[Project workspace: .../projects/<project_id>/iterations/...]`
   in your dispatch description). Per-project namespacing prevents
   files from one project clobbering another's local staging dir.

3. **Strict spec compliance rules** —
   - Real benchmarks: use `datasets.load_dataset(...)` for HuggingFace
     datasets (GSM8K, MATH, SVAMP, etc.). **Do not embed a synthetic
     mock dataset** unless Stage 5 explicitly says synthetic.
   - All IVs from Stage 4/5 must be present as configurable
     parameters or `argparse` flags.
   - All DVs from Stage 4/5 must appear as keys in the output JSONL
     schema.
   - Seeds: use `random.seed(seed); np.random.seed(seed); torch.manual_seed(seed)`.
   - Temperature & sampling params: read from Stage 5 spec.
   - k values: parameterised, never hardcoded outside the
     pre-registered set.
   - **Chat-model inference: ALWAYS use `tokenizer.apply_chat_template`**
     when calling an instruct/chat model (Qwen-Instruct, Llama-Instruct,
     Mistral-Instruct, etc.). Raw prompt strings cause the model to keep
     generating "Human: ... Assistant: ..." Q&A pairs until it hits
     `max_new_tokens`, producing truncated garbage with 0% accuracy.
     The pattern:

         messages = [{"role": "user", "content": prompt}]
         input_ids = tokenizer.apply_chat_template(
             messages, add_generation_prompt=True, return_tensors="pt"
         ).to(device)
         out = model.generate(
             input_ids,
             max_new_tokens=N,
             do_sample=False,                       # greedy for temperature=0
             eos_token_id=tokenizer.eos_token_id,   # MUST set to stop cleanly
             pad_token_id=tokenizer.pad_token_id or tokenizer.eos_token_id,
         )
         response = tokenizer.decode(
             out[0][input_ids.shape[1]:],            # slice off the prompt
             skip_special_tokens=True,
         )

     The Stage 6a critic auto-REJECTs implementations that call
     `model.generate(input_ids=tokenizer(prompt).input_ids, ...)` (raw
     prompt, no chat template) — that's the no-stop-token failure mode
     observed in a prior run.

4. **Output format** —
   - Use `JSONL` output (one record per problem/seed/condition cell)
     UNLESS Stage 5 mandates something else.
   - Schema: include every IV + every DV + a `run_id` field that
     the runner can correlate with `fast_query_exp_status`.
   - At the very end, print a clearly delimited
     `=== RESULT_JSON: {...} ===` block summarising aggregate
     metrics, so the runner's `log_tail` capture sees it.

5. **MANDATORY: a `--smoke` mode** —
   The driver script MUST support a `--smoke` flag (or equivalent CLI
   switch) that runs a radically shrunken version of the full
   experiment. This is non-negotiable. It exists so the Stage 6b runner
   can prove the pipeline actually works before committing to the full
   run, catching any architectural bug (wrong worker pool config,
   broken data loader, hung dependency, missing remote asset, OOM at
   small scale, etc.) in ≤5 min instead of after hours of wasted GPU
   time.

   Three hard rules for `--smoke`:

   - **Same code path. ALL of them.** `--smoke` MUST exercise the same
     functions, same imports, same I/O paths, same worker setup AS WELL
     AS every inference / generation path the full run will use. A
     separate `smoke.py` that bypasses the real code is forbidden — it
     would defeat the purpose. **`if args.smoke: skip_pilots = True`
     and similar "fast-path the smoke" shortcuts are also forbidden** —
     they skip pilot inference functions whose bugs (e.g. a second
     copy of `generate()` that forgot `apply_chat_template`) won't
     surface until the full run is hours in.

     Use a config-level switch (e.g. `N_PROBLEMS = 5 if args.smoke
     else FULL_N`) that the existing loops respect, applied to EACH
     path. If your full run does `determinism_pilot()` then
     `extraction_pilot()` then `census()`, your smoke does
     `determinism_pilot(n=2)` then `extraction_pilot(n=2)` then
     `census(n=5)` — all three, just smaller. The Stage 6a critic
     D11 grep auto-REJECTs `skip_pilots = ... args.smoke` patterns.

     If you have multiple inference functions, they MUST call the same
     internal `generate()` (DRY). One source of truth means smoke
     validates the same `generate()` the full run uses. The single
     biggest source of "smoke passed but full produced garbage" is
     two copies of generate where only one was fixed.

   - **Same output schema.** `--smoke` writes the same JSONL fields
     and prints the same `=== RESULT_JSON: ... ===` block, just with
     a tiny sample size. The runner / critic should not need to know
     a row came from smoke vs full to parse it.

   - **Tight budget: ≤5 min wall-clock, end-to-end.** Pick the
     smallest sample that touches every stage of the pipeline:
       - LLM inference: 5 problems (or 1 problem × 5 conditions)
       - Training: ~100 steps (enough to verify gradient flow)
       - Hyperparameter sweep: 1 cell (cheapest config)
       - Simulation: 5 trajectories
       - Statistical sampling: N = 5
     If your experiment can't smoke-test in 5 min, redesign it; the
     full run will be too brittle to debug.

   Implementation hint: add `argparse` flag `--smoke` (store_true).
   Inside the script, set `n_problems = 5 if args.smoke else FULL_N`,
   and use that constant in the existing loop. One-line change to the
   loop; no duplicate code path.

## Phase 4 — Push to the remote working dir (MANDATORY)

**Writing code locally is not enough.** If you stop here, the
Stage 6b runner has no code to execute, and the Stage 6a critic
will REJECT for failed push verification (D4). Every file in
`/tmp/stage6_impl/<project_id>/` MUST end up on the remote.

### Step 4.1 — Choose the **per-project remote subdir**

Each project gets its own remote subdir to prevent collisions with:
- Previous Stage 6a runs (from this or other projects)
- Other researchers' code in the shared working dir (e.g. Alice's
  `stage6_experiment/` from an earlier study)

Convention: push to `omc/<project_id>/iter_<iteration_id>/` relative
to the assigned remote working dir. Example: if your project_id is
`2628bae4a2b6` and iteration is `iter_001`, the remote target prefix
is `omc/2628bae4a2b6/iter_001/`.

Extract `<project_id>` and `<iteration_id>` from the
`[Project workspace: ... /projects/<project_id>/iterations/<iter_id>]`
line in your dispatch task description.

### Step 4.2 — Load the experiment-infra credentials

```bash
load_skill("experiment-infra")    # gives you fast_*.sh and credentials path
```

### Step 4.3 — Push every file with the per-project prefix

```bash
PROJECT_ID="<extracted_id>"          # from dispatch task description
ITER_ID="<extracted_iter>"           # e.g. iter_001
REMOTE_PREFIX="omc/${PROJECT_ID}/${ITER_ID}"

export INFRA_SERVER_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["server_url"])' "$SKILL_DIR/experiment_infra_credentials.json")"
export INFRA_SESSION_KEY="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["session_key"])' "$SKILL_DIR/experiment_infra_credentials.json")"

# Every file goes under the per-project prefix.
bash "$SKILL_DIR/scripts/fast_push_code.sh" \
    "/tmp/stage6_impl/${PROJECT_ID}/experiment.py" \
    "${REMOTE_PREFIX}/experiment.py"

bash "$SKILL_DIR/scripts/fast_push_code.sh" \
    "/tmp/stage6_impl/${PROJECT_ID}/benchmarks.py" \
    "${REMOTE_PREFIX}/benchmarks.py"
# ...one per file
```

### Step 4.4 — Verify push succeeded

```bash
bash "$SKILL_DIR/scripts/fast_query_working_dir.sh" --max-depth 4 \
    | grep -A 20 "${PROJECT_ID}"
```

Every file you pushed in Step 4.3 must appear under
`${REMOTE_PREFIX}`. **A pushed-but-not-verified file is the same as
a not-pushed file. A failed push must be reported, not silently
swallowed.**

If a push fails (returncode != 0, or the file does not appear in
fast_query_working_dir), DO NOT proceed to submit_result. Document
the failure in the receipt's "Push status" column as `❌ <error>`
and STOP — the critic will mark D4 as FAIL and trigger retry. Better
to fail loud here than to ship a missing file.

## Phase 5 — Write the implementation receipt

Create `stage6_implementation_receipt.md` in the project workspace.
Required sections:

```markdown
# Stage 6a — Implementation Receipt

## 1. Tasks completed
For each implementation task from Stage 5 assignments:
  ### TN — <task description verbatim>
  - Spec source: stage5_experiment_designer.md §X
  - Local file: /tmp/stage6_impl/<filename>.py
  - Lines: <N>
  - Remote path: <remote/path>
  - Push verification: ✅ confirmed in fast_query_working_dir output
  - Spec compliance — implemented components:
    - IV1: <component>  →  <line range in code>
    - IV2: ...
    - DV1: ...
  - Open ambiguities (if any): <list>

## 2. Aggregate file map
| Local file | Lines | Remote path | Push status |
|------------|-------|-------------|-------------|
| ...        | ...   | ...         | ✅ / ❌      |

## 3. Spec coverage matrix
For every IV / DV / parameter from Stage 4/5 contract, list which
file + function implements it. Anything in the contract not in a
row here is a spec gap.

## 4. Runnable entrypoint
The command the runner (Stage 6b) should invoke, with the
per-project remote subdir prefix:

  ### Smoke (runner runs this FIRST, ≤5 min)
    cd omc/<project_id>/<iter_id> && python experiment.py --smoke --benchmark gsm8k --seed 42

  ### Full (runner runs this only if smoke succeeded)
    cd omc/<project_id>/<iter_id> && python experiment.py --benchmark gsm8k --k 5 --seed 42 ...

State explicitly what `--smoke` shrinks (e.g. "5 problems instead of
1319, otherwise identical code path, identical schema, expected
wall-clock ≤5 min").

## 5. Limitations / explicit non-coverage
Anything from Stage 5 that you could NOT implement (e.g. PAL
sandbox requires gVisor that may not be on remote). Be explicit;
don't paper over.
```

## Phase 6 — Submit

```
submit_result(summary="Stage 6a Implementation: <N> files pushed to remote (X lines), spec coverage <K/K>, <gap_count> ambiguities documented. Runner entrypoint: python experiment.py ...")
```

## What NOT to do

- **Don't stop after writing code locally.** Writing to
  `/tmp/stage6_impl/` is step ONE. If you don't push to the remote
  AND don't write the receipt, the runner has nothing to execute and
  the critic will REJECT for missing push + missing receipt. This
  failure mode has happened before — be the implementer who finishes
  the job.
- **Don't push to the flat working dir.** The remote working dir is
  shared across projects and across other researchers. Always push
  under the `omc/<project_id>/<iter_id>/` prefix so your files don't
  clobber (or get clobbered by) anyone else's leftover code.
- **Don't embed mock / synthetic data when Stage 5 specified real
  benchmarks.** This is the worst possible failure mode — it makes
  the entire experiment meaningless. The Stage 6a critic
  auto-REJECTs if Stage 5 said "GSM8K" and you used a hardcoded
  list of problems.
- **Don't add IVs or DVs not in Stage 4/5.** Adding "temperature
  sweep" or "alternative verifier" when the spec didn't ask for it
  is improvisation. Document the spec gap, do not paper over it
  with extra code.
- **Don't redesign the verifier or aggregation.** If Stage 5 says
  "pass@k with sympy normalisation", implement exactly that; don't
  substitute "majority vote with regex matching" because it's
  easier.
- **Don't skip the push verification.** A pushed-but-not-verified
  file is the same as a not-pushed file for the runner.
- **Don't echo `INFRA_SESSION_KEY`.** The experiment-infra runbook
  covers this; the same rule applies in receipts.

## Multi-implementer hand-off (future)

This runbook is written for a single code-implementer employee. If
multiple employees with `code_implementer` skill are dispatched in
parallel, each takes a disjoint subset of the assignments table
(by task ID). Your receipt must list which TIDs you handled so the
critic can aggregate across implementers without double-counting.

## Degraded mode (no remote available)

If `fast_query_budget.sh` fails (credentials missing, infra down),
you cannot push code. In that case:
- Still write the code locally to `/tmp/stage6_impl/`.
- Mark every "Push status" cell as ❌ with the specific error.
- Write the receipt anyway; runner will read it and decide what to
  do (probably BLOCKED).
- Set submit summary to start with `[DEGRADED]`.

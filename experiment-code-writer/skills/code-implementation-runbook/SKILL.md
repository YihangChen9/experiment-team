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

**Stage 5 is the SINGLE SOURCE OF TRUTH — it supersedes the original
CEO task / topic.** Stage 4 and Stage 5 exist precisely to refine and
correct the initial idea: the debate may have changed parameters,
equalised budgets, dropped a confound, or tightened a control that the
CEO's one-line task got wrong. When `stage5_experiment_designer.md`
(or `stage4_methodology_designer.md`) specifies a value that differs
from the CEO task in your dispatch description or your memory — e.g.
`max_new_tokens`, sample size, seeds, decoding params, number of
conditions — **implement the Stage 5 value, NOT the CEO task value.**
Stage 5 always wins. A real failure (run be7144a49333): Stage 5 locked
`max_new_tokens=256` for *both* conditions to eliminate a truncation
confound, but the code used `{"direct": 16, "cot": 256}` "because the
CEO task said 16/256" — the Stage 6a critic auto-REJECTed it (D1/D2
contract violation) and the whole stage failed. In your receipt's
spec-coverage matrix, cite the Stage 5 section (`stage5_…md §N`) for
every parameter — never the CEO task.

**Default mode: ADAPT, not REWRITE.** Stage 5 produces a file called
`stage5_codebase_pin.md` that names the upstream codebase you must
clone and lists the exact files + lines you will change. Your job is
to honour that pin — clone, validate, patch the named lines, and
keep everything else untouched. Writing from scratch is the
*exception path* (used only when the pin file explicitly says NO
USABLE UPSTREAM FOUND), and it triggers extra critic scrutiny.

## Phase 0 — Honour the Stage 5 upstream pin

### Step 0.0 — RETRY? Inventory existing state FIRST (MANDATORY)

If your task description contains retry feedback (a stub warning, a
critic rejection, "previous attempt..."), a previous attempt may have
already done most of the work. **Do NOT restart the analysis from
zero** — a real run (083041abd013) burned all 4 attempts re-discovering
the same facts and died of step exhaustion each time, with the actual
code sitting finished in `upstream/` and only the receipt missing.

Inventory what already exists, in this order, and SKIP every step whose
output is already on disk:

```bash
ls <project_workspace>/upstream 2>/dev/null && cd <project_workspace>/upstream && git log --oneline -3   # adaptation commit already there?
ls /tmp/stage6_impl/<project_id>/ 2>/dev/null                          # from-scratch staging already there?
read("stage6_implementation_receipt.md")                               # receipt already drafted?
bash "$SKILL_DIR/scripts/fast_query_working_dir.sh" --max-depth 4 | grep <project_id>   # already pushed?
```

Then complete ONLY the missing tail of the pipeline (typically: push →
receipt → submit). If the code is written and pushed and only the
receipt is missing, write the receipt and submit — that is a 2-minute
finish, not a fresh task. Record in the receipt that this attempt
resumed from prior state.

Read `stage5_codebase_pin.md` from the project workspace first.

```python
read("stage5_codebase_pin.md")
```

### Step 0.1 — If a pin exists (the common path)

The pin file lists:

- `Repository:` — the upstream URL
- `Commit:` — a SHA, NOT a branch name
- `License:` — must be MIT / Apache-2.0 / BSD or equivalent
- `Adaptation surface:` — file-by-file list of allowed changes with LOC estimate
- `Test command:` — the upstream's own test suite that must pass

Execute:

```bash
cd <project_workspace>
git clone --depth 1 <Repository> upstream
cd upstream
git fetch --depth 1 origin <Commit>
git checkout <Commit>

# Verify license matches the pin (refuse to proceed on mismatch)
head -3 LICENSE || head -3 LICENSE.md || (echo "FATAL: pin claims MIT/Apache but no LICENSE file" && exit 2)

# Run upstream's own tests on a clean checkout BEFORE patching
<Test command from pin>     # capture exit code; see classification below
```

**Classify the pre-patch test result** — this is the single most
mis-handled step:

| Symptom in stdout | Classification | What to do |
|---|---|---|
| `ModuleNotFoundError`, `ImportError`, `pip install` failures, pyarrow/CMake build errors on macOS, missing CUDA, etc. | **Environment failure** — upstream code is fine, your local machine just can't run its tests | **Continue to Step 0.2.** Mark `pretest_status: SKIPPED_ENV` in your receipt. The remote runner will exercise tests on Linux where they pass. |
| Actual `AssertionError`, `FAILED tests/...`, or any failure from the pin's named test command after a successful import | **Real upstream defect** — the pin is broken | **Stop.** `submit_result(status: error, summary="Stage 6a aborted: pin's upstream tests fail on clean checkout — pin must be amended in Stage 5")` and paste the failing test output. Do not patch a broken baseline. |
| Exit 0, all tests pass | **Healthy** | Continue. Mark `pretest_status: PASSED`. |

Do **not** invent a third interpretation ("environmental, I'll patch
to /tmp instead"). Patches always go into the cloned `upstream/`
directory; only the classification of pre-patch tests changes.

### Step 0.1.5 — Patch plan BEFORE you edit a single line (MANDATORY)

Do not start editing files the moment the clone lands. Plan the
patches first — write before code. The pin already tells you *what*
to change; this step makes you state *how*, and self-check that the
how stays inside the contract, before any `Edit` runs. It is a
~30-line thinking step that prevents the most expensive 6a failure:
realising mid-edit that the spec is ambiguous or that you need a
file the pin never listed, after you have already half-patched the
tree.

This is a **lightweight** plan (the pin's adaptation surface table
is already precise — do not re-derive it). For each row of that
table, state in working memory one line:

```
<file path> : <what changes> ← pin row / Stage 5 §<n>  | risk: <one phrase>
```

Then run this self-check before proceeding to Step 0.2 — **all five
must be YES**, or you stop and `submit_result(status: error)`
instead of improvising:

1. Every file I plan to touch appears in the pin's adaptation surface table.
2. I am NOT planning to touch the upstream extractor / scorer / dataset loader (sacred — see Step 0.3).
3. Each planned change maps to a concrete spec line; none is "while I'm here" scope creep.
4. My planned edits stay within the table's LOC estimate (±50%).
5. The plan adds no new IV/DV/parameter/metric beyond the Stage 4/5 contract.
6. Every numeric/config value I will hardcode (max_new_tokens, seeds, sample sizes, decoding params, n_conditions) matches `stage5_experiment_designer.md` / `stage4_methodology_designer.md` **exactly** — NOT the CEO task. If the CEO task and Stage 5 disagree, I am using the Stage 5 value. (Run be7144a49333 died here: code used the CEO task's `max_new_tokens=16` for the direct condition; Stage 5 had locked `256` for both.)

If any answer is NO, the pin is wrong or insufficient — that is a
Stage 5 amendment, not something you fix by editing more files.
Stop and report. Record this plan + checklist outcome in the
receipt (Phase 5 §0.5).

### Step 0.2 — Apply the patches the pin lists, **IN PLACE inside upstream/**

For each row of the `Adaptation surface` table, modify the file named
in the row directly inside the cloned `upstream/` tree. Use the
`Edit` tool on existing files; use `Write` for new files with the
**full upstream-relative path** (e.g.
`upstream/lm_eval/tasks/gsm8k/utils.py`).

**Do NOT** stage patches in `/tmp/stage6_impl/` when a pin exists.
That path is reserved for the from-scratch exception in Step 0.4.
Staging patches outside `upstream/` was a historical failure mode —
the runner then pushes the unpatched upstream/ and your work is
silently lost.

Rules:

1. Edit the named file in place inside `upstream/`.
2. Stay within the LOC estimate ±50%.
3. **Do not modify files not listed in the table.** If you find you
   need to touch one, stop and surface that via
   `submit_result(status: error)` — the pin should be amended in
   Stage 5, not in Stage 6.
4. After all patches: `cd upstream && git add -A && git commit -m "Stage 6 adaptation: <one-liner>"` so reviewers can
   `git diff <pinned_commit> HEAD` and see exactly what changed.

### Step 0.3 — Re-run the upstream tests after patching (env-aware)

```bash
cd upstream && <Test command from pin>
```

Classify the post-patch result with the same table as Step 0.1:

- **PASSED** → continue. Mark `posttest_status: PASSED` in receipt.
- **SKIPPED_ENV** → continue. Mark `posttest_status: SKIPPED_ENV`.
  The remote runner will exercise tests on Linux. Document in
  receipt that local validation was env-blocked.
- **Real failure (your patch broke something)** → roll the failing
  patch back, re-scope, and repeat Step 0.2. **The upstream
  extractor / scorer / dataset loader is sacred — do not patch
  them; if you think you need to, Stage 5 picked the wrong
  upstream.**

### Step 0.3.5 — If the pin itself is BROKEN (hallucinated commit / files)

Distinct from failing tests: sometimes the pin names a commit that
does not exist (`git fetch origin <sha>` → "couldn't find remote ref")
or an adaptation-surface file that is absent from the tree (real case:
pin named `simple_evals/gsm8k_eval.py`; the repo only has
`mgsm_eval.py`). Stage 5 hallucinated — handle it pragmatically, in
this order:

1. **Commit unreachable but repo + adaptation surface valid** → resolve
   to `origin/HEAD`, document the deviation in the receipt
   (`pin_deviation: commit <sha> unreachable, resolved to <head_sha>`),
   and continue the pin path.
2. **Named files absent / adaptation surface impossible** → the pin is
   unusable. Take the from-scratch path (Step 0.4) and record
   `path_taken: from-scratch (pin broken: <one-line reason>)` in the
   receipt §0 — the Stage 6 critic and the engine surface this to
   Stage 5 so the pin author learns.

Either way: decide ONCE, write the decision into the receipt
immediately, and move on. Do not re-litigate the pin on a retry —
Step 0.0's inventory will show the decision already made.

### Step 0.4 — If the pin says NO USABLE UPSTREAM FOUND

You write from scratch, but the bar is higher:

- Your `experiment.py` MUST include the three-stage locked answer
  extractor (regex → SymPy → LLM-judge fallback) described in the
  Stage 5 §4.3 paragraph.
- You MUST ship a `tests/test_extractor.py` with at least 100 hand-
  graded examples covering numeric / fractional / negative /
  scientific-notation answer formats. The Stage 6 critic checks for
  this fixture; missing fixture = D-CODEBASE FAIL.
- Document in your implementation receipt (Phase 5) that you took
  the from-scratch exception path and why no upstream worked.

### Step 0.5 — Commit your patches, then skip ahead

**The pin path replaces Phases 1–3 (which assume from-scratch
staging in `/tmp/stage6_impl/`).** When Phase 0 finishes, you have
already written your code in place inside `upstream/`. Do NOT read
Phases 1, 2, 3 — they do not apply to you.

Before leaving Phase 0:

```bash
cd <project_workspace>/upstream
git add -A
git commit -m "Stage 6 adaptation: <one-liner naming the patches>"
git log --oneline <pinned_commit>..HEAD     # capture this for the receipt
```

If `git status --short` returns anything after the commit, your
patches are not all staged — fix it before continuing. A clean
working tree with one new commit on top of `<pinned_commit>` is the
exit condition for Phase 0.

**Your next phase is Phase 4 (push to remote).** Then Phase 5
(receipt) and Phase 6 (submit). The engine hard-gates 6a→6b on the
receipt + a clean upstream/ — uncommitted patches or a missing
receipt = automatic retry of this whole phase.

---

> **Phases 1, 2, 3 below are the FROM-SCRATCH PATH** (Step 0.4 only).
> If a pin existed and Phase 0 finished, jump directly to Phase 4.

## Phase 1 — Read the contract (from-scratch path only)

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

## Phase 2 — Identify implementation tasks (from-scratch path only)

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

## Phase 2.5 — Implementation plan BEFORE you write code (MANDATORY)

The from-scratch path has no pin to keep you honest, so this is
where you write the plan *before* the code. This is the single
highest-leverage step on this path: an LLM writing a benchmark
driver from a prose spec drifts — it forgets an IV, invents a
metric, or hardcodes a synthetic dataset — and the Stage 6a critic
only catches it after you have written and pushed everything, then
the whole 6a→6b cycle restarts. A few minutes planning here saves
that.

This is an **implementation** plan (how you will *translate* the
contract into files), NOT a design plan. You do not decide what to
test, which datasets, or which metrics — Phase 1's contract table
already fixed all of that. You only decide how to lay it out in
code.

For each task from Phase 2, write in working memory:

```
### TN — <task>
- Target file(s): experiment.py / benchmarks.py / ...
- Key functions / classes I will write: <names + one-line purpose>
- Contract coverage — each row maps to where it lands in code:
    IV1 <name>  → <file>::<function> (argparse flag / config const)
    DV1 <name>  → output JSONL field
    benchmark   → datasets.load_dataset("...") in <file>
    k / seeds / temperature → <where>
- The single internal generate() (DRY) lives in: <file>::generate
- --smoke shrink point: N_PROBLEMS = 5 if args.smoke else FULL_N, used in <loop>
- Risks / ambiguities: <list, or "none">
```

Then run this self-check — **all must be YES** before any `Write`:

1. Every IV, DV, parameter, benchmark, k value, and seed setting in the Phase 1 contract table appears in a "contract coverage" line above. (Anything in the contract not mapped = a gap you must resolve now, not after writing.)
2. I am adding NOTHING outside the contract — no extra IV/DV, no extra metric, no "nice to have" sweep.
3. There is exactly ONE internal `generate()`; every inference path calls it (so `--smoke` validates the same code the full run uses).
4. Real benchmarks use `datasets.load_dataset(...)`; I am not embedding synthetic/mock data unless Stage 5 explicitly said synthetic.
5. `--smoke` is a config-level shrink of the SAME code path, not a separate fast path or `skip_pilots` shortcut.
6. **The pure-logic functions are import-safe and CPU-only.** Answer extraction, scoring, prompt formatting, and the output-schema builder are plain functions that take inputs and return outputs — no GPU, no `datasets.load_dataset`, no `model.generate`, no network at *module import time* or inside these functions. All GPU/dataset/model work lives behind `if __name__ == "__main__":` or inside a `run()` the CLI calls. **Reason:** Phase 3.5 will `import` your module and unit-test these functions locally (no GPU on this machine). If importing the module loads a 7B model or hits HuggingFace, the local test loop cannot run and the bug-prone logic ships untested.

In your Phase 2.5 plan, add one line per task naming the pure-logic functions you will test locally:

```
- Locally testable (pure, CPU): extract_answer(text)->int|None, score(pred,gold)->bool, build_prompt(q)->str
```

If a contract item cannot be mapped (the spec is ambiguous on it),
**do not improvise** — document the ambiguity in the receipt
(Phase 5 §0.5) and, if it blocks implementation, surface it via
`submit_result(status: error)`. Record the plan + checklist outcome
in the receipt.

## Phase 3 — Write the code (from-scratch path only)

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
   - **Parallelism-first (batch by default — the runtime ships vLLM).**
     An experiment is an embarrassingly parallel grid: every
     (problem × condition × seed) cell is independent. Do NOT write a
     `for` loop that calls `model.generate()` once per example — that
     runs one forward pass at a time and turns a real dataset (1k–10k
     items) into a multi-hour single-process job, the timeout we keep
     hitting. **Flatten every independent cell into ONE prompt list and
     hand it to a batching engine.** The default runtime image
     (`vllm_w_flashattn`) has **vLLM 0.11.0** preinstalled — that is the
     intended inference path, not raw `transformers` looping:

         from vllm import LLM, SamplingParams
         llm = LLM(model=MODEL_PATH, dtype="bfloat16",
                   gpu_memory_utilization=0.90, max_model_len=4096,
                   trust_remote_code=True)            # load ONCE
         sp = SamplingParams(temperature=0.0, max_tokens=256)  # greedy
         # Build the FULL workload: every cell of the grid, flattened.
         convs = [[{"role": "user", "content": build_prompt(cell)}]
                  for cell in all_cells]               # cheap, no GPU
         outs = llm.chat(convs, sp)                    # ONE call; vLLM
                                                       # batches internally
         texts = [o.outputs[0].text for o in outs]     # aligned to all_cells

     `llm.chat(...)` applies the model's chat template internally (so the
     "ALWAYS use the chat template" rule below is satisfied for free), and
     vLLM does continuous batching + paged KV-cache, so you get
     throughput without hand-tuning batch sizes. `--smoke` passes a
     SHORT `all_cells` (5 cells) to the SAME `llm.chat` call — identical
     code path, fewer prompts.

     If (and only if) vLLM genuinely cannot serve the model (e.g. an
     architecture it doesn't support), fall back to HF transformers with
     **bounded micro-batches** — left-pad + `attention_mask`, a fixed
     `BATCH_SIZE` tuned to VRAM — NOT one-example-at-a-time and NOT one
     giant batch of everything. The static gate (Phase 4) flags
     per-example `generate()` in a loop as an ERROR.

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

   - **Model loading: load onto ONE explicit device — `device_map="cuda:0"`,
     NEVER `device_map="auto"`** (for a single model that fits on one GPU,
     which is every ≤~30B model on an 80 GB card). Use exactly what Stage 5 /
     the reference template specifies:

         model = AutoModelForCausalLM.from_pretrained(
             MODEL_PATH,
             torch_dtype=torch.bfloat16,
             device_map="cuda:0",          # single device — NOT "auto"
             local_files_only=True, trust_remote_code=True,
         )

     Why this matters (real failure, run 1c9befd9a898): the code used
     `device_map="auto"`. On a contended GPU, `accelerate` silently shards
     the model across GPU + CPU ("Some parameters are on the meta device
     because they were offloaded to the cpu"), then OOMs at the first
     `model.generate()` — a confusing mid-run crash. With an explicit
     `device_map="cuda:0"`, a too-full GPU fails LOUDLY at load time
     (clear error, no CPU offload, no silent activation OOM). Do not
     "improve" the spec's `cuda:0` into `"auto"` — Stage 5's loading
     kwargs are part of the locked contract (see the Stage-5-authoritative
     rule above). The Stage 6a critic flags `device_map="auto"` as a
     spec deviation.

   - **HF fallback only: memory-safe, load-once, BOUNDED-BATCH inference.**
     (Prefer vLLM per the Parallelism-first rule above; this block is for
     when vLLM cannot serve the model.) `device_map` is only one of a
     family of mistakes that each cause an OOM or a load failure mid-run.
     Use this canonical pattern — note the loop is over **batches**, not
     individual examples — and run the checklist below; each line prevents
     a specific crash we have hit or will hit:

         # ── load ONCE, at module __main__ / run() start — NEVER inside the loop ──
         tok = AutoTokenizer.from_pretrained(
             MODEL_PATH, local_files_only=True, trust_remote_code=True)
         tok.padding_side = "left"         # decoder-only: left-pad so gen aligns
         model = AutoModelForCausalLM.from_pretrained(
             MODEL_PATH,
             torch_dtype=torch.bfloat16,   # NEVER omit → default fp32 = 2× VRAM = OOM
             device_map="cuda:0",          # single device, NOT "auto"
             local_files_only=True,        # offline node: NO HuggingFace hub download
             trust_remote_code=True,
         )
         model.eval()
         ...
         BATCH_SIZE = 16                   # tune to VRAM; bounded, not 1, not all-N
         prompts = [tok.apply_chat_template(m, add_generation_prompt=True,
                                            tokenize=False) for m in all_msgs]
         for i in range(0, len(prompts), BATCH_SIZE):   # loop over BATCHES
             enc = tok(prompts[i:i + BATCH_SIZE], return_tensors="pt",
                       padding=True).to(model.device)
             with torch.inference_mode():  # NEVER omit → grad buffers accumulate → OOM
                 out = model.generate(**enc, max_new_tokens=N, do_sample=False,
                                      eos_token_id=tok.eos_token_id,
                                      pad_token_id=tok.pad_token_id or tok.eos_token_id)

     **Pre-push checklist — every line YES, or you OOM/crash on the remote:**
     1. Model + tokenizer loaded **exactly once**, outside the per-problem
        loop (grep your code: `from_pretrained` must NOT be inside any `for`).
     2. `torch_dtype` is set to the Stage 5 dtype (bf16) — never left to
        default (fp32 doubles VRAM).
     3. `device_map="cuda:0"` (or the spec's value) — never `"auto"`.
     4. `MODEL_PATH` is the exact **local** path from Stage 5
        (`/mnt/data0/hf_models/...`), not a hub id like `"Qwen/..."` —
        `local_files_only=True` so a wrong path fails loud instead of
        silently downloading.
     5. Every `model.generate()` is inside `with torch.inference_mode():`.
     6. Inputs are moved to `model.device` (not a hardcoded `"cuda"`).
     7. Inference is **batched**, not one-example-at-a-time. Prefer vLLM
        (`llm.chat(all_convs)` — continuous batching handles VRAM for you).
        On the HF fallback, use **bounded micro-batches** (left-pad +
        `attention_mask`, a fixed `BATCH_SIZE`) — never a `for problem in
        problems: model.generate(...)` loop (sequential = hours; static
        gate ERROR), and never one unbounded giant batch of all N (KV-cache
        for N×long sequences OOMs). Bounded batches are the middle path.
     8. `eos_token_id` + `pad_token_id` are passed (clean stop).

     Record "GPU inference checklist: PASS" in the receipt (§0.6 area). The
     Stage 6a critic spot-checks these; a `from_pretrained` inside a loop,
     a missing `torch_dtype`, `device_map="auto"`, or per-example
     `model.generate()` in a loop is a D-CODE deviation.

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

## Phase 3.5 — Local test loop (from-scratch path only, MANDATORY)

The from-scratch path has no upstream `pytest` to keep it honest, so
the first time this code *executes* is the remote Stage 6b smoke run —
minutes + GPU away. A wrong regex in `extract_answer`, an off-by-one
in `score`, a `build_prompt` that drops the question: none of these
are caught by the static gate (they parse and lint clean), and each
one silently produces 0% accuracy that looks like a "model is bad"
result, not a "your extractor is broken" bug. This loop catches that
class locally, in ~1 s, before any push.

You CANNOT run the full experiment locally (no GPU, no datasets on
this machine). You CAN — and must — unit-test the **pure-logic
functions** you flagged in the Phase 2.5 plan (answer extraction,
scoring, prompt building, output-schema). That is where the
silent-accuracy-killing bugs live.

### Step 3.5.1 — Write `test_<driver>.py`

Next to your driver (e.g. `/tmp/stage6_impl/<project_id>/test_experiment.py`),
write a small pytest file with **hand-graded** assertions — you, the
author, decide the expected output for each input, so the test
encodes intent, not whatever the code happens to do:

```python
from experiment import extract_answer, score, build_prompt

def test_extract_answer_plain():
    assert extract_answer("The answer is 42.") == 42
def test_extract_answer_last_int_fallback():
    assert extract_answer("first 7 then 13") == 13
def test_extract_answer_none_when_absent():
    assert extract_answer("no number here") is None
def test_score_exact():
    assert score(42, 42) is True
    assert score(41, 42) is False
def test_build_prompt_contains_question():
    assert "What is 2+2?" in build_prompt("What is 2+2?")
```

Cover, at minimum: each pure function's happy path, one edge case
(empty / no-match / boundary), and the failure mode you most worry
about (usually answer extraction — the #1 cause of "smoke passed,
accuracy 0").

### Step 3.5.2 — Run the loop: plan → code → test → score → refine

```bash
cd /tmp/stage6_impl/<project_id>
python3 "$SKILL_DIR/scripts/static_gate.py" .        # syntax + lint
python3 -m pytest -q test_experiment.py              # pure-logic tests
```

**Score this iteration** — both must hold:
- `static_gate: OK` (or warnings-only), AND
- pytest: all collected tests pass.

| Result | Action |
|---|---|
| Both green | Done — proceed to Phase 4. |
| pytest fails | Read the assertion. Decide: is the CODE wrong (fix `experiment.py`) or is the TEST wrong (you mis-stated the expected value)? Fix the right one with `Edit`, re-run. |
| import error in the test | Your pure logic is NOT import-safe (it ran GPU/dataset code at import). Move that work behind `__main__` / into `run()`. This is the Phase 2.5 self-check #6 failing late — fix it now. |
| static gate `[error]` | Fix the syntax/undefined-name, re-run. |

### Step 3.5.3 — Failure-mode router (classify, then fix the RIGHT way)

A "test failed" is not one thing. Before you edit, **classify** the
failure and apply the matching fix — treating every failure the same
wastes iterations (e.g. re-running on a timeout, or rewriting logic on
an import error). Tag the dominant failure in this round and act:

| Failure tag | Signal | Targeted fix (do this, not a blind rewrite) |
|---|---|---|
| **syntax** | `SyntaxError`, `IndentationError`, static-gate `[error]` parse | Minimal edit to the exact line; do NOT touch logic. Re-gate. |
| **import** | `ImportError` / `ModuleNotFoundError` at test import | Two sub-cases: (a) your pure logic ran GPU/dataset code at import → move it behind `__main__`/`run()` (Phase 2.5 #6); (b) a genuinely missing dep → it's pre-installed on the remote, so guard the import or move it into the function, don't `pip install` locally. |
| **test** (assertion) | `AssertionError`, wrong value | Decide CODE-wrong vs TEST-wrong: recompute the expected value by hand. If the code is wrong, fix the function; if your hand-graded expectation was wrong, fix the test. Never weaken the assertion to pass. |
| **lint** | ruff/pyflakes warning (non-error) | Fix only if cheap (unused import, undefined name). Style nits don't block — proceed. |
| **timeout** | the test itself hangs / >30s | Your pure-logic test must NOT do GPU/dataset/network work. If it does, you tested the wrong layer — move the heavy call out and test only the pure function. |
| **runtime** | `TypeError`/`KeyError`/`ValueError` in the function under test | A real logic bug the test caught — exactly what this loop is for. Fix the function, re-run. |

Pick the tag, apply its row, re-run. One classified fix per iteration
beats shotgun edits.

**Hard cap: 3 iterations.** This is a loop, not an infinite refine.
After 3 rounds:
- If green → proceed.
- If still red → STOP iterating. Record in the receipt (§0.6) exactly
  which tests fail and why you could not resolve them in budget, then
  proceed to Phase 4 anyway (a documented known-failing test is far
  better than silently shipping untested logic — the Stage 6a critic
  and the 6b smoke run are the backstops). Do NOT delete or weaken the
  failing test to force green; that defeats the entire purpose.

### Why a cap, and why proceed-on-fail

The loop exists to catch cheap bugs cheaply, not to chase a perfect
score. Three honest iterations catch the vast majority of extractor /
scorer bugs. Beyond that, you are likely blocked on something the
local environment can't resolve (a dataset-shape assumption, a
tokenizer quirk) that the remote smoke run will surface anyway — so
spend the budget there, with the failure documented, rather than
looping locally forever.

## Phase 4 — Push to the remote working dir (MANDATORY)

**Writing code locally is not enough.** If you stop here, the
Stage 6b runner has no code to execute, and the Stage 6a critic
will REJECT for failed push verification (D4). Every file you
modified (or created) MUST end up on the remote.

### Step 4.0 — Local static gate BEFORE any push (MANDATORY)

Pushing code that does not even parse wastes a full remote
smoke-run cycle (minutes + GPU) to discover a one-line
`SyntaxError` or a missing import. Catch that class of bug
locally, in ~1s, before it leaves this machine. This mirrors how a
good coding agent surfaces compiler/LSP errors the instant a file
is written, instead of after execution.

Run the bundled gate over **every** `.py` file you wrote or
patched:

```bash
# Pin path — check the whole patched tree
python3 "$SKILL_DIR/scripts/static_gate.py" <project_workspace>/upstream/

# From-scratch path — check the staged files
python3 "$SKILL_DIR/scripts/static_gate.py" /tmp/stage6_impl/<project_id>/
```

The gate runs, per file: `ast` syntax parse → `py_compile` →
(if available) `ruff`/`pyflakes` for undefined names and unused
imports. `$SKILL_DIR` is your skill directory; if it is not set,
use the absolute path to this runbook's `scripts/static_gate.py`.

Interpret the result:

| Gate output | Meaning | What to do |
|---|---|---|
| `static_gate: OK` (exit 0) | All files parse and lint clean | Proceed to Step 4.1 |
| `STATIC ERRORS detected` with `[error]` lines (exit 1) | Real defects (SyntaxError, undefined name, bad import) | **Fix every `[error]` with `Edit`, then re-run the gate.** Do NOT push. |
| `warnings only` (exit 0) | Style/lint nits, no blockers | May proceed; fix if cheap |
| `linter: none` note | Neither `ruff` nor `pyflakes` installed | Syntax/compile still ran; optionally `pip install ruff` for undefined-name coverage, then re-run |

**Do not push, do not write the receipt, do not `submit_result`
until the gate exits 0 (or warnings-only).** A push of code that
fails the static gate is the same avoidable failure as a missing
push — the Stage 6b smoke run will simply fail on import, and the
6a→6b cycle restarts. Loop fix→re-gate until clean.

### Pin path vs from-scratch path — what gets pushed

- **Pin path (Phase 0.2 ran)** — push the entire `upstream/`
  directory tree under the per-project prefix. Source root is
  `<project_workspace>/upstream/`. The runner will then `cd
  <REMOTE_PREFIX>/upstream/` and invoke the entrypoint named in
  your receipt (e.g. `lm_eval --model ...`).
- **From-scratch path (Phase 0.4 ran)** — push the contents of
  `/tmp/stage6_impl/<project_id>/` under the per-project prefix.
  The runner will then `cd <REMOTE_PREFIX>/` and invoke
  `python experiment.py ...`.

Both paths use the same remote-prefix convention (Step 4.1). Pick
the right source root for your case.

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

### Step 4.5 — Environment designation + dependency pre-flight (MANDATORY)

Your entrypoint will execute via `run_local` **in a conda environment on
the host** — NOT inside the docker runtime image. The image's package
list (vLLM etc.) does NOT apply to run_local. Two hard facts learned
from a double-failure (run 284fe7b69d4f burned all retries on this):

1. **The default env is bare.** A bare `python ...` entrypoint runs in
   the default env, which may lack vLLM entirely. Every entrypoint MUST
   begin with `source <conda_bin>/activate <env> && ...`.
2. **`fast_query_server_info` only tracks torch / vllm / flash_attn per
   env. It is NOT a package inventory.** Never infer that `datasets`,
   `scipy`, `pandas`, … are missing (or present) from it — that exact
   wrong inference made the previous run designate a `vllm`-only env
   while two fully-stocked envs sat unused.

So BEFORE you write the receipt's §4 entrypoint, run a **dependency
pre-flight probe**: one `run_local` CPU job (seconds, $0) that checks
every top-level import your pushed code makes, across the candidate
envs:

```bash
DEPS='"vllm","datasets","transformers","scipy","numpy"'   # ← every top-level import in YOUR code
bash "$SKILL_DIR/scripts/fast_submit.sh" --config "$SKILL_DIR/assets/base.conf.json" -c \
  'for e in base r3l opsd infra; do echo "=== env: $e ==="; source /home/zsgpu/miniconda3/bin/activate $e && python -c "import importlib.util as u; [print(m, (\"OK\" if u.find_spec(m) else \"MISSING\")) for m in ['"$DEPS"']]"; done'
# poll fast_query_exp_status until succeeded, read log_tail
```

Designate the env where **every** dep is OK (prefer one with
`flash_attn` for inference workloads). Paste the probe's per-env matrix
into the receipt §4 under "Environment designation".

**If NO conda env has all deps → BUILD the environment yourself: the
`uv-venv` strategy** (issue #117 — typical for non-LLM / CPU
experiments: Bayesian optimization, classical ML, simulation, whose
stacks like gpytorch/botorch are not preinstalled anywhere).

**Iron rule: the environment is fully built and import-verified BEFORE
any experiment run.** The runner installs NOTHING at experiment time —
it receives a ready `.venv` and just executes. All of this uses the
existing fast_submit run_local path (zero infra changes). Verified
live: `run_479a2234f20a` (uv venv + install + run works; host has uv,
pypi reachable) and `run_322bfa5384e0`→`run_c4e98cd53fa2` (the `.venv`
persists in the remote workspace across runs).

Your obligations, in order:

1. **Ship a pinned `requirements.txt`** next to your code and push it
   in Phase 4 like any other file. Every top-level import in your code
   maps to a pinned line. For torch-using CPU experiments note
   `# cpu-only` at the top (the env-build keeps torch on the CPU
   index — no multi-GB CUDA download).
2. **Submit the ENV-BUILD run** (after the Phase 4 push, before the
   receipt): copy `assets/uv_venv_local.yaml` (from the
   experiment-infra skill), fill `<project_id>/<iter_id>` and the
   import list (EVERY top-level import your code makes), submit via
   `fast_submit.sh --yaml`, poll to `succeeded`, and confirm
   `"env_ready": true` in the log_tail. This builds
   `omc/<project_id>/<iter_id>/.venv` once; it persists for all
   subsequent runs.
3. Receipt §4 says:
   - `env_strategy: uv-venv`
   - `env_build_run: run_...` + the env-build RESULT_JSON (the proof
     the env exists and imports verified)
   - `gpu_required: false | true` (false → runner skips the GPU pick)
   - smoke/full entrypoints written as `.venv/bin/python
     experiment.py ...` — NO conda prefix, NO install steps.

If the env-build run fails (a dep cannot resolve / needs a GPU build
unavailable on the host), fix requirements.txt and re-submit the
env-build; only `submit_result(status: error)` if it genuinely cannot
work. Do NOT hand the runner an unbuilt or unverified environment.

## Phase 5 — Write the implementation receipt (MANDATORY, ALWAYS)

**This step is non-negotiable.** The Stage 6b runner reads
`stage6_implementation_receipt.md` to find the runnable entrypoint;
without it, 6b reports `BLOCKED: missing receipt` and the entire
6a → 6b → critic cycle has to restart. Skipping the receipt is
the single most common failure mode and the Stage 6a critic
auto-REJECTs on its absence.

You write this file even if a step earlier failed. A receipt
with `pretest_status: SKIPPED_ENV` and a partial task list is
still better than no receipt — it tells the runner what state
the workspace is in, what's pushed, and whether to proceed.

Create `stage6_implementation_receipt.md` in the project workspace.
Required sections:

```markdown
# Stage 6a — Implementation Receipt

## 0. Pin status (REQUIRED — fill before anything else)
- `path_taken`: pin | from-scratch
- `pretest_status`: PASSED | SKIPPED_ENV | NOT_RUN
- `posttest_status`: PASSED | SKIPPED_ENV | NOT_RUN
- If SKIPPED_ENV, paste the first 5 lines of the failing
  install/import error so the runner knows what's expected to
  fail on Linux too (vs what was macOS-only).

## 0.5 Implementation plan (REQUIRED — written before code)
- `plan_self_check`: PASS | FAIL — the pre-code checklist from
  Step 0.1.5 (pin path) or Phase 2.5 (from-scratch path).
- Paste the per-file/per-task plan you wrote before editing.
- Ambiguities found during planning (or "none"). If any blocked
  implementation, note the `submit_result(status: error)` you raised.

## 0.6 Local test loop (REQUIRED on from-scratch path; "N/A — pin path" otherwise)
- `local_test_status`: PASS | FAIL_DOCUMENTED | SKIPPED_PIN
- `iterations_used`: <0-3> of the Phase 3.5 budget.
- Test file: `/tmp/stage6_impl/<project_id>/test_<driver>.py` (<N> tests).
- Paste the final `pytest -q` summary line (e.g. `5 passed in 0.3s`,
  or `4 passed, 1 failed`).
- If `FAIL_DOCUMENTED`: name each still-failing test and the one-line
  reason it could not be resolved in 3 iterations (e.g. "depends on
  tokenizer output only available on the GPU host"). Do NOT report
  PASS for a loop you did not actually run.

## 1. Tasks completed
For each implementation task from Stage 5 assignments:
  ### TN — <task description verbatim>
  - Spec source: stage5_experiment_designer.md §X
  - Local file: upstream/<sub/path>.py (pin path) OR
                /tmp/stage6_impl/<filename>.py (from-scratch path)
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

### Environment designation (REQUIRED — Step 4.5 evidence)
- `env_strategy`: `<conda env name, e.g. r3l>` | `uv-venv`
- `gpu_required`: true | false
- Pre-flight probe run_id: `run_...`
- Per-env import matrix from the probe log (paste it)
- If `uv-venv`: `requirements`: `omc/<project_id>/<iter_id>/requirements.txt`
  (pinned, pushed in Phase 4; `# cpu-only` header if torch should come
  from the CPU index), `env_build_run`: `run_...` (the SUCCEEDED
  env-build with `"env_ready": true` — paste its RESULT_JSON), and the
  entrypoints below are `.venv/bin/python experiment.py ...` — the env
  is already built; the runner installs nothing.

The command the runner (Stage 6b) should invoke, with conda
activation and the per-project remote subdir prefix:

  ### Smoke (runner runs this FIRST, ≤5 min)
    source /home/zsgpu/miniconda3/bin/activate <env> && cd omc/<project_id>/<iter_id> && python experiment.py --smoke --benchmark gsm8k --seed 42

  ### Full (runner runs this only if smoke succeeded)
    source /home/zsgpu/miniconda3/bin/activate <env> && cd omc/<project_id>/<iter_id> && python experiment.py --benchmark gsm8k --k 5 --seed 42 ...

State explicitly what `--smoke` shrinks (e.g. "5 problems instead of
1319, otherwise identical code path, identical schema, expected
wall-clock ≤5 min").

## 5. Limitations / explicit non-coverage
Anything from Stage 5 that you could NOT implement (e.g. PAL
sandbox requires gVisor that may not be on remote). Be explicit;
don't paper over.
```

## Phase 6 — Submit (only after Phase 5 has produced the receipt)

```
submit_result(summary="Stage 6a Implementation: <N> files pushed to remote (X lines), spec coverage <K/K>, <gap_count> ambiguities documented. Runner entrypoint: python experiment.py ...")
```

Before you call `submit_result`, re-verify by reading the receipt
back from disk:

```
read("stage6_implementation_receipt.md")    # must return non-empty content
```

If this read returns empty / not-found, Phase 5 wasn't actually
executed — go back and do it. **A submit_result without a
corresponding receipt on disk is auto-REJECT by Stage 6a critic.**

## What NOT to do

- **Don't stage pin patches in `/tmp/stage6_impl/`.** When a pin
  exists (Step 0.1 found `stage5_codebase_pin.md`), patches go
  **in place inside `upstream/`** — that is the cloned tree the
  runner pushes to remote. Writing to `/tmp` for the pin path
  means your work never reaches the runner and 6b reports
  BLOCKED. The historical failure mode: LLM hits a macOS env
  error on pre-patch tests, rationalises "tests are
  environmental, I'll proceed with patches", and then writes
  every patch to `/tmp` instead of `upstream/`. Don't be that
  LLM. The env-failure classification (Step 0.1 table) lets you
  proceed with in-place patching — use it.
- **Don't stop after writing code locally.** Writing to
  `/tmp/stage6_impl/` (from-scratch path) or to `upstream/`
  (pin path) is step ONE. If you don't push to the remote
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
- **Don't skip the local static gate (Step 4.0).** Pushing code
  that fails `ast`/`py_compile` means the remote smoke run dies on
  import after spending minutes + GPU to discover a one-line typo.
  Run `static_gate.py`, fix every `[error]`, re-run until clean —
  then push. The gate is local and costs ~1s; skipping it is never
  worth the wasted remote cycle.
- **Don't skip the Phase 3.5 local test loop (from-scratch).** The
  static gate proves the code *parses*; it does NOT prove your
  `extract_answer` regex is right. An untested extractor that returns
  `None` on every real output looks identical to "the model scored 0%"
  — and you only find out hours into the full run. Write the hand-graded
  pytest, run it locally, iterate ≤3×. If it can't go green in budget,
  document the failing test in receipt §0.6 — never weaken the test to
  force green.
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

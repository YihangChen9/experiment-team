---
name: experiment-execution-runbook
description: Stage 6b runbook. One simple flow per runner task: submit → poll-loop in a single bash → write evidence report → submit_result. No phases, no branches, no early-exit.
allowed-tools: Bash, Read, Write
---

# Stage 6b — Auto Experiment Executor

You translate `stage5_assignments.md` rows into real remote runs.
**You do exactly four steps**. They are not phases, they are a
checklist. You go 1 → 2 → 3 → 4 and you MUST finish step 4 before
terminating. If any step hits an error, you still finish 3 and 4 —
recording the error is the output.

Step 1 is itself a two-substep gate: **always submit a `--smoke` run
first** and only proceed to the full run if smoke reaches
`succeeded` in ≤5 min. This catches architectural bugs (hung
workers, broken loaders) before any hour-long GPU burn. Stage 6a is
required by `code-implementation-runbook` D11 to expose `--smoke`;
trust it.

If you ever feel like ending early, you are wrong. **STEP 3 (write
file) and STEP 4 (submit_result) are non-negotiable.** The historical
failure mode is an LLM polling for 9 minutes, then quietly stopping
without ever calling `write()` or `submit_result()`. Don't be that
LLM.

## Step 0 — Boilerplate (one-shot setup)

```
read("stage5_assignments.md")
read("stage6_implementation_receipt.md")
load_skill("experiment-infra")
```

Extract `<project_id>` and `<iter_id>` from your workspace path
(`.../projects/<project_id>/iterations/<iter_id>`). All your remote
work lives at `omc/<project_id>/<iter_id>/`. The receipt's "Runnable
entrypoint" tells you the exact command Stage 6a wants run.

If `stage6_implementation_receipt.md` is missing, jump straight to step 3
and write a report with `status: blocked`, then step 4.

## Step 1 — Submit (one `fast_submit.sh` per runner row)

For each row whose Skill column contains `experiment_runner`, run ONE
fast_submit and capture the run_id immediately into a shell variable.
**Record the run_id at submit time** — every later step (polling,
status query, cancel, evidence capture, the final report) needs it. If
you lose it, you cannot recover the run state. Non-runner rows (e.g.
`causal-inference`, `paper_writer`) — note as deferred, no fast_submit.

**Critical: submit the smoke run FIRST**, not the full run. The
implementation MUST expose a `--smoke` flag that runs a tiny subset
through the same code path (per `code-implementation-runbook`). The
runner uses this as a 5-minute proof-of-pipeline before committing
hours of GPU to a full run that may hang on an architectural bug
(wrong worker pool config, broken loader, hung dependency).

```bash
# Step 1a — submit the smoke run first
SMOKE_RID=$(bash "$SKILL_DIR/scripts/fast_submit.sh" \
  --config "$SKILL_DIR/assets/base.conf.json" \
  -c "cd omc/<project_id>/<iter_id>/ && python experiment.py --smoke <other args>" \
  2>&1 | tee /tmp/submit_smoke.log | grep -oE 'run_[a-f0-9]+' | head -1)
echo "SMOKE_RID=$SMOKE_RID"
```

Then poll it (use the same single-bash-with-sleep pattern from Step
2). If smoke does not reach `succeeded` within 5 min (one 5-min
bash batch), abort:

```bash
# Step 1b — wait for smoke. 5 min cap; don't extend.
RID="$SMOKE_RID"
DEADLINE=$(( $(date +%s) + 300 ))   # 5 minutes
while :; do
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "SMOKE_TIMEOUT — implementation likely hung"
    bash "$SKILL_DIR/scripts/fast_cancel.sh" "$RID" || true
    break
  fi
  STATUS=$(bash "$SKILL_DIR/scripts/fast_query_exp_status.sh" "$RID" --summary 2>/dev/null \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("status",""))' 2>/dev/null)
  case "$STATUS" in
    succeeded) echo "SMOKE_OK"; break ;;
    failed|rejected) echo "SMOKE_FAIL status=$STATUS"; break ;;
  esac
  sleep 15
done
```

- `SMOKE_OK` → proceed to **Step 1b' (quality check)** below before
  submitting full.
- `SMOKE_FAIL` or `SMOKE_TIMEOUT` → **DO NOT SUBMIT THE FULL RUN.**
  Skip ahead to Step 3 (write report) with status `blocked_smoke_failure`,
  attach the smoke run_id + log_tail. The Stage 6a Code Writer needs
  to fix the implementation before any retry burns more GPU. This is
  the safety net for hung-pipeline bugs.

## Step 1b' — Smoke quality check (don't trust "succeeded")

A smoke run that returns ``succeeded`` can still produce **garbage
results**: e.g. the implementation hits ``max_new_tokens`` on every
example because the chat template wasn't applied, so accuracy is 0%
and truncation rate is 100%. Tech-success ≠ scientific-success.

After SMOKE_OK, fetch the smoke `RESULT_JSON` (printed at end of run
into the log_tail) and validate:

```bash
# Pull smoke's full log_tail (no --summary so we get the RESULT_JSON block)
SMOKE_TAIL=$(bash "$SKILL_DIR/scripts/fast_query_exp_status.sh" "$SMOKE_RID" 2>/dev/null)

# Extract the RESULT_JSON block (the impl prints `=== RESULT_JSON: {...} ===`)
RESULT=$(echo "$SMOKE_TAIL" | python3 -c '
import sys, json, re
data = sys.stdin.read()
# Try parsing as a status response with log_tail field
try:
    obj = json.loads(data)
    tail = obj.get("log_tail", "") or data
except Exception:
    tail = data
m = re.search(r"=== ?RESULT_JSON:?\s*(\{.*?\})\s*===", tail, re.DOTALL)
print(m.group(1) if m else "")
')

# Parse the key metrics
QUALITY=$(echo "$RESULT" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
except Exception:
    print("NO_RESULT_JSON"); raise SystemExit
# Drill into census / aggregate (impl-specific keys; adapt as needed)
cen = r.get("census", r)
acc_d = cen.get("accuracy_direct", cen.get("accuracy_a", None))
acc_c = cen.get("accuracy_cot",    cen.get("accuracy_b", None))
trunc_d = cen.get("direct_truncated", 0)
trunc_c = cen.get("cot_truncated", 0)
n = cen.get("n_problems", 0) or 1
trunc_rate = (trunc_d + trunc_c) / max(2*n, 1)
# Quality gate: both accuracies known AND at least one > 0 AND trunc_rate < 0.5
if acc_d is None or acc_c is None:
    print("NO_METRICS")
elif acc_d == 0.0 and acc_c == 0.0:
    print(f"QUALITY_FAIL_ACCURACY_ZERO acc_d={acc_d} acc_c={acc_c}")
elif trunc_rate >= 0.5:
    print(f"QUALITY_FAIL_TRUNCATED rate={trunc_rate:.2f}")
else:
    print(f"QUALITY_OK acc_d={acc_d} acc_c={acc_c} trunc_rate={trunc_rate:.2f}")
')
echo "QUALITY=$QUALITY"
```

- `QUALITY_OK` → proceed to Step 1c (submit full).
- `QUALITY_FAIL_ACCURACY_ZERO` / `QUALITY_FAIL_TRUNCATED` / `NO_RESULT_JSON` /
  `NO_METRICS` → **DO NOT SUBMIT FULL.** Skip to Step 3 with status
  `blocked_smoke_invalid` and paste the QUALITY line + smoke RESULT_JSON
  as evidence. The Stage 6a Code Writer must fix the inference loop
  (likely missing `apply_chat_template`, no stop tokens, or wrong
  `max_new_tokens`) before any retry.

The quality gate exists because in a real run we observed: smoke
returned `succeeded`, RESULT_JSON had `accuracy_direct=0, accuracy_cot=0,
direct_truncated=3/3, cot_truncated=3/3` — the model was generating
"Human: ... Assistant: ..." Q&A pairs forever, hitting max_tokens, and
the regex grabbed random numbers from the runaway text. A 1-line
quality gate would have caught this in 5 minutes instead of burning
hours on a doomed full run.

```bash
# Step 1c — submit the full run, only if SMOKE_OK AND QUALITY_OK
RUN_ID_T1=$(bash "$SKILL_DIR/scripts/fast_submit.sh" \
  --config "$SKILL_DIR/assets/base.conf.json" \
  -c "cd omc/<project_id>/<iter_id>/ && python experiment.py <other args>" \
  2>&1 | tee /tmp/submit_t1.log | grep -oE 'run_[a-f0-9]+' | head -1)
echo "RUN_ID_T1=$RUN_ID_T1"
```

You DO NOT need to do anything fancy with credentials, working_dir
queries, or server_info queries. The experiment-infra runbook covers
the credential exports. Skip every optional query — every extra call
burns iteration budget.

## Step 2 — Poll to terminal in a SINGLE bash call (~9 min max)

This is one bash invocation. Do not split it into many small polls —
that's the failure pattern. Use a `while` loop with `sleep 30` inside
ONE bash call. The LangChain bash tool caps at 600s, so do batches of
9 minutes; if the experiment is still running after that, you simply
re-issue the same loop for another batch.

```bash
RID="$RUN_ID_T1"
DEADLINE=$(( $(date +%s) + 540 ))   # 9 minutes
while :; do
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "BATCH_EXPIRED status=still_running"
    break
  fi
  STATUS_JSON=$(bash "$SKILL_DIR/scripts/fast_query_exp_status.sh" "$RID" --summary 2>/dev/null)
  STATUS=$(echo "$STATUS_JSON" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("status",""))' 2>/dev/null)
  case "$STATUS" in
    succeeded|failed|rejected)
      echo "TERMINAL status=$STATUS"
      break
      ;;
  esac
  sleep 30
done
```

After the bash returns, look at the last echo line:
- `TERMINAL status=succeeded|failed|rejected` → go to step 3.
- `BATCH_EXPIRED status=still_running` → you have a budget choice:
  - If you have agent iterations to spare, re-run the same bash once
    more (another 9-min batch). Up to **2 re-runs** total — so worst
    case 27 min of wall-clock polling. **Do NOT re-run more than 2
    times.** After 2 re-runs, go to step 3 with `status: still_running`.

Capture final evidence (only when status is terminal) with **one** more
bash call to get full `log_tail` / metrics:

```bash
bash "$SKILL_DIR/scripts/fast_query_exp_status.sh" "$RID" > /tmp/evidence_t1.json
```

## Step 3 — Write `stage6_experimentalist.md` (MANDATORY, ALWAYS)

Even if step 1 failed. Even if step 2 hit `still_running`. Even if
credentials were missing. **You write this file before submit_result.**
It is a `write()` tool call. If you skip it, the critic auto-REJECTS
and the entire Stage 6b retry cycle restarts.

Template (copy verbatim, fill placeholders, save with `write()`):

```markdown
# Stage 6 — Auto Experiment Results

## Tasks executed (Path A — remote runner)

### T<N> — <verbatim task description from stage5_assignments.md>
- run_id: <RID>
- submitted_at: <ISO timestamp from infra response>
- finished_at: <ISO timestamp, or "still_running">
- status: succeeded | failed | rejected | still_running | blocked
- estimated_cost: $<X.XX>
- actual_cost: $<Y.YY>
- key metrics: <JSON snippet from response.metrics>
- log_tail excerpt (last 40 lines):
  ```
  <paste tail from /tmp/evidence_<rid>.json>
  ```

(repeat per runner row)

## Tasks deferred (Path B — non-runner skills)

| # | Task | Assignee | Skill | Reason |
|---|------|----------|-------|--------|
| T<N> | ... | ... | ... | Not in Stage 6 scope; awaiting Stage 7 |

## Errors / blocks

(empty if none — else paste the literal error and which step it failed in)

## Aggregate summary

- tasks executed: <N>
- tasks deferred: <M>
- tasks blocked: <K>
- total actual cost: $<X.XX>
- overall verdict: ALL_SUCCEEDED | PARTIAL | BLOCKED
```

If you don't have data for a field, write `unknown` or `N/A`. **Do not
omit fields and do not skip the file.** A partial file with honest
"unknown" values is fine; an empty file is auto-REJECT.

## Step 4 — submit_result (MANDATORY, AFTER step 3)

```
submit_result(summary="Stage 6: <N> remote runs (<succ>/<fail>/<still_running>), <M> deferred, total $<X.XX>. See stage6_experimentalist.md for run_ids and log_tails: <RID_T1>, <RID_T2>, ...")
```

The summary string must be **at least 100 characters** and must reference
`stage6_experimentalist.md`. Stub summaries like `"Executed: bash"` or
`"Done."` are the historical auto-REJECT trigger — they signal to the
critic that no work was performed.

## Hard rules

- **Never terminate without step 3 AND step 4.** If you find yourself
  thinking "I'm done, I'll just stop now" — you are not done, you have
  to do step 3 (write file) and step 4 (submit_result) before stopping.
- **Never fabricate run_ids or metrics.** If submit failed, write
  `status: failed` and paste the error in `## Errors / blocks`.
- **Never simulate when a runner is available.** If the skill is
  `experiment_runner` and the infra is reachable, you MUST really submit
  via `fast_submit.sh`. Describing what would happen is auto-REJECT.
- **Never run experiments locally on the OMC host.** Remote execution
  goes through experiment-infra.
- **Never echo `INFRA_SESSION_KEY`.**

## Degraded mode (no infra available)

If step 0's `fast_query_budget.sh` (or any step 1 fast_submit) fails
with missing env vars / unreachable host:

- Write the template in step 3 with status=`blocked` and the literal
  error pasted in the Errors section.
- Step 4 submit_result summary begins with `[BLOCKED]` and references
  the report file as usual.

The critic will mark this as BLOCKED, not REJECTED — you did the right
thing by surfacing the failure with evidence, instead of fabricating.

"""Tests for static_gate.py — focus on the sequential-inference (#13) check.

The runbook's default runtime image ships vLLM 0.11.0. Stage 6a code that
calls `model.generate()` once per example inside a Python `for` loop is the
N×-latency anti-pattern that turns a real dataset into a multi-hour
single-process run. The static gate must catch that BEFORE push and steer
the implementer to vLLM batched / continuous-batching inference.

Run with the engine repo's venv:
    .venv/bin/python -m pytest <this file> -q
"""
from __future__ import annotations

import importlib.util
import pathlib

_SG_PATH = pathlib.Path(__file__).resolve().parent / "static_gate.py"
_spec = importlib.util.spec_from_file_location("static_gate", _SG_PATH)
static_gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(static_gate)


def _errors(source: str) -> list:
    """Run the sequential-inference check and return only gating errors."""
    diags = static_gate._sequential_inference_check("experiment.py", source)
    return [d for d in diags if d.severity == "error"]


# --- The anti-pattern the gate exists to catch ---------------------------

def test_per_example_generate_in_for_loop_is_flagged():
    src = (
        "import torch\n"
        "from transformers import AutoModelForCausalLM, AutoTokenizer\n"
        "model = AutoModelForCausalLM.from_pretrained('m')\n"
        "for problem in problems:\n"
        "    ids = tok.apply_chat_template(problem, return_tensors='pt')\n"
        "    out = model.generate(ids, max_new_tokens=256)\n"
    )
    errs = _errors(src)
    assert len(errs) == 1, f"expected exactly one perf error, got {errs}"
    assert "vLLM" in errs[0].message or "vllm" in errs[0].message


def test_enumerate_loop_over_examples_is_flagged():
    src = (
        "from transformers import AutoModelForCausalLM\n"
        "for i, example in enumerate(dataset):\n"
        "    out = model.generate(encode(example))\n"
    )
    assert len(_errors(src)) == 1


# --- Correct / exempt patterns must NOT be flagged -----------------------

def test_vllm_batched_generate_not_flagged():
    """vLLM's offline engine does continuous batching internally — passing the
    whole prompt list to one llm.generate() is the desired pattern, even if it
    sits inside a loop over conditions."""
    src = (
        "from vllm import LLM, SamplingParams\n"
        "llm = LLM(model='m')\n"
        "for condition in conditions:\n"
        "    outs = llm.generate(all_prompts, sampling_params)\n"
    )
    assert _errors(src) == []


def test_batch_loop_over_dataloader_not_flagged():
    """`for batch in loader: model.generate(batch)` IS batched inference — the
    loop iterates over batches, not individual examples."""
    src = (
        "from transformers import AutoModelForCausalLM\n"
        "for batch in dataloader:\n"
        "    out = model.generate(batch, max_new_tokens=256)\n"
    )
    assert _errors(src) == []


def test_range_stride_batch_loop_not_flagged():
    """The canonical HF bounded-batch fallback from the runbook: stride over the
    data in BATCH_SIZE chunks. `range(0, N, BATCH_SIZE)` (3-arg) is a batch
    stride, not per-example iteration."""
    src = (
        "from transformers import AutoModelForCausalLM\n"
        "BATCH_SIZE = 16\n"
        "for i in range(0, len(prompts), BATCH_SIZE):\n"
        "    enc = tok(prompts[i:i + BATCH_SIZE], return_tensors='pt', padding=True)\n"
        "    out = model.generate(**enc, max_new_tokens=256)\n"
    )
    assert _errors(src) == []


def test_slice_batch_loop_not_flagged():
    """A loop that slices the dataset by the loop variable is batching, even if
    the variable name isn't 'batch'."""
    src = (
        "from transformers import AutoModelForCausalLM\n"
        "for start in range(0, n, bs):\n"
        "    chunk_ids = encode(data[start:start + bs])\n"
        "    out = model.generate(chunk_ids)\n"
    )
    assert _errors(src) == []


def test_generate_outside_loop_not_flagged():
    src = (
        "from transformers import AutoModelForCausalLM\n"
        "out = model.generate(all_ids, max_new_tokens=256)\n"
    )
    assert _errors(src) == []


def test_loop_not_referencing_iter_var_in_generate_not_flagged():
    """A loop over seeds that runs a fully-batched generate (whose inputs do
    NOT depend on the loop variable) is not the per-example anti-pattern."""
    src = (
        "from transformers import AutoModelForCausalLM\n"
        "for seed in seeds:\n"
        "    torch.manual_seed(seed)\n"
        "    out = model.generate(all_prompt_ids, max_new_tokens=256)\n"
    )
    assert _errors(src) == []


def test_no_generate_at_all_not_flagged():
    src = "x = 1\nfor i in range(10):\n    x += i\n"
    assert _errors(src) == []


# --- It must gate end-to-end through main() ------------------------------

def test_main_blocks_on_sequential_inference(tmp_path, capsys):
    f = tmp_path / "experiment.py"
    f.write_text(
        "from transformers import AutoModelForCausalLM\n"
        "for problem in problems:\n"
        "    out = model.generate(encode(problem))\n",
        encoding="utf-8",
    )
    rc = static_gate.main([str(f)])
    assert rc == 1, "sequential inference must block the push (exit 1)"
    out = capsys.readouterr().out
    assert "vLLM" in out or "vllm" in out

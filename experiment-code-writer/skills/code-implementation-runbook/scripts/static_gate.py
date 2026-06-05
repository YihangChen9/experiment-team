#!/usr/bin/env python3
"""Local static gate for Stage 6a code — the Python analogue of opencode's
post-edit LSP feedback loop.

opencode's edit tool, right after writing a file, pulls LSP diagnostics and
appends them to the tool result ("LSP errors detected in this file, please
fix") so the agent fixes syntax/undefined-name bugs *before* the change
propagates. We have no LSP here, but `ast` + `py_compile` (stdlib) plus an
optional `ruff`/`pyflakes` pass catch the same class of cheap, high-frequency
bugs — and we run them locally, on macOS, before any push to the remote infra.

Why this matters for Stage 6a specifically: without it, a `SyntaxError` or a
missing import only surfaces after push → remote smoke run (minutes + GPU).
This gate moves that feedback to ~1s, local, before Phase 4.

Usage:
    python static_gate.py FILE [FILE ...]
    python static_gate.py DIR            # checks every *.py under DIR
    python static_gate.py upstream/      # pin path
    python static_gate.py /tmp/stage6_impl/<project_id>/   # from-scratch path

Exit code:
    0  — all files clean (no errors)
    1  — at least one file has errors (block the push, fix, re-run)
    2  — bad invocation (no files given / path not found)

Output: an opencode-style diagnostic block grouped by file. Only ERRORS gate
the push; ruff/pyflakes warnings are printed but do not fail the run.
"""

from __future__ import annotations

import ast
import os
import py_compile
import shutil
import subprocess
import sys

# Cap mirrors opencode's "report top 20 diagnostics per file" (lsp/diagnostic.ts)
MAX_PER_FILE = 20


class Diagnostic:
    def __init__(self, line: int, col: int, message: str, severity: str = "error"):
        self.line = line
        self.col = col
        self.message = message
        self.severity = severity

    def render(self) -> str:
        loc = f"{self.line}:{self.col}" if self.col else str(self.line)
        return f"  [{self.severity}] {loc}  {self.message}"


def _collect_py_files(args: list[str]) -> list[str]:
    files: list[str] = []
    for arg in args:
        if os.path.isdir(arg):
            for root, _dirs, names in os.walk(arg):
                # skip the usual noise so we don't lint vendored deps
                if any(p in root for p in (".git", "__pycache__", ".venv", "node_modules")):
                    continue
                for n in names:
                    if n.endswith(".py"):
                        files.append(os.path.join(root, n))
        elif arg.endswith(".py"):
            files.append(arg)
        else:
            print(f"static_gate: skipping non-python path: {arg}", file=sys.stderr)
    # de-dup, stable order
    seen = set()
    out = []
    for f in files:
        rp = os.path.realpath(f)
        if rp not in seen:
            seen.add(rp)
            out.append(f)
    return out


def _syntax_check(path: str, source: str) -> list[Diagnostic]:
    """Stage 1: ast.parse — the cheapest, most decisive check (fatal SyntaxError)."""
    try:
        ast.parse(source, filename=path)
        return []
    except SyntaxError as e:
        return [Diagnostic(e.lineno or 0, e.offset or 0, f"SyntaxError: {e.msg}")]


def _compile_check(path: str) -> list[Diagnostic]:
    """Stage 2: py_compile — backstop for things ast misses (e.g. encoding)."""
    try:
        py_compile.compile(path, doraise=True)
        return []
    except py_compile.PyCompileError as e:
        return [Diagnostic(0, 0, f"py_compile: {e.msg.strip()}")]


# Loop-variable names that signal the loop already iterates over BATCHES, so a
# `.generate()` inside is correct batched inference, not the per-example
# anti-pattern. Anything else (problem / example / row / prompt / i / ...) that
# the generate call actually consumes means one forward pass per item.
_BATCH_LIKE_NAMES = frozenset({
    "batch", "batches", "minibatch", "mini_batch", "batched", "chunk", "chunks",
    "bucket", "buckets", "shard", "shards", "group", "groups", "window", "windows",
})

_SEQUENTIAL_INFERENCE_MSG = (
    "PERF: per-example `.generate()` inside a `for` loop over `{var}` — "
    "sequential inference runs one forward pass per item (N× latency = hours on "
    "a real dataset, the single-process timeout we keep hitting). The default "
    "runtime image ships vLLM 0.11.0: build the FULL prompt list and pass it to "
    "`llm.generate(prompts, sampling_params)` (vLLM does continuous batching + "
    "paged KV internally), or use bounded HF micro-batches (left-pad + "
    "attention_mask, batch_size tuned to VRAM). Flatten independent cells "
    "(problems × conditions × seeds) into ONE batched workload. See "
    "code-implementation-runbook Phase 3 'Parallelism-first'."
)


def _imports_vllm(tree: ast.AST) -> bool:
    """True if the module imports vllm at all — vLLM's offline engine batches
    internally, so we never flag a file that uses it."""
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(a.name == "vllm" or a.name.startswith("vllm.") for a in node.names):
                return True
        elif isinstance(node, ast.ImportFrom):
            if (node.module or "").split(".")[0] == "vllm":
                return True
    return False


def _name_ids(node: ast.AST) -> set[str]:
    return {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}


def _is_batch_stride_loop(loop: ast.For) -> bool:
    """`for i in range(start, stop, step)` with an explicit step strides over
    batches, not individual examples."""
    it = loop.iter
    return (
        isinstance(it, ast.Call)
        and isinstance(it.func, ast.Name)
        and it.func.id == "range"
        and len(it.args) >= 3
    )


def _slices_by_targets(loop: ast.For, targets: set[str]) -> bool:
    """True if the loop body slices a collection using a loop target
    (e.g. `prompts[i:i + BATCH_SIZE]`) — a batching signal."""
    for node in ast.walk(loop):
        if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Slice):
            if _name_ids(node.slice) & targets:
                return True
    return False


def _sequential_inference_check(path: str, source: str) -> list[Diagnostic]:
    """Stage 4 (#13): flag the per-example `model.generate()`-in-a-loop
    anti-pattern that turns a real dataset into a multi-hour single-process run.

    Precise + low false-positive: only flags a `.generate(...)` call that (a)
    sits inside a `for` loop, (b) references that loop's iteration variable in
    its arguments (so it is genuinely one forward pass per item), and (c) the
    loop variable is NOT batch-like. Files that import vLLM are exempt — its
    engine batches internally.
    """
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError:
        return []  # _syntax_check already reports this
    if _imports_vllm(tree):
        return []

    seen_lines: set[int] = set()
    diags: list[Diagnostic] = []
    for loop in ast.walk(tree):
        if not isinstance(loop, ast.For):
            continue
        targets = _name_ids(loop.target)
        if not targets or (targets & _BATCH_LIKE_NAMES):
            continue
        # Batch-stride loops are correct batching, not per-example iteration:
        #   for i in range(0, N, BATCH_SIZE): ...generate(data[i:i+BATCH_SIZE])
        # Signals: a 3-arg range() (explicit step), or slicing a collection by
        # the loop variable anywhere in the body.
        if _is_batch_stride_loop(loop) or _slices_by_targets(loop, targets):
            continue

        # Taint propagation: the iteration variable, plus any variable assigned
        # (transitively) from it inside the loop body, is "per-example". This
        # catches the common `ids = apply_chat_template(problem); generate(ids)`
        # indirection, not just `generate(problem)`.
        tainted = set(targets)
        assigns: list[tuple[set[str], set[str]]] = []  # (lhs_names, rhs_names)
        for sub in loop.body:
            for node in ast.walk(sub):
                if isinstance(node, ast.Assign):
                    lhs = set().union(*(_name_ids(t) for t in node.targets))
                    assigns.append((lhs, _name_ids(node.value)))
                elif isinstance(node, (ast.AnnAssign, ast.AugAssign)) and node.value is not None:
                    assigns.append((_name_ids(node.target), _name_ids(node.value)))
        changed = True
        while changed:
            changed = False
            for lhs, rhs in assigns:
                if (rhs & tainted) and not (lhs <= tainted):
                    tainted |= lhs
                    changed = True

        for sub in loop.body:
            for call in ast.walk(sub):
                if not (isinstance(call, ast.Call)
                        and isinstance(call.func, ast.Attribute)
                        and call.func.attr == "generate"):
                    continue
                referenced: set[str] = set()
                for a in call.args:
                    referenced |= _name_ids(a)
                for kw in call.keywords:
                    if kw.value is not None:
                        referenced |= _name_ids(kw.value)
                hit = referenced & tainted
                if hit and call.lineno not in seen_lines:
                    seen_lines.add(call.lineno)
                    var = sorted(hit & targets)[0] if (hit & targets) else sorted(hit)[0]
                    diags.append(Diagnostic(
                        call.lineno, call.col_offset,
                        _SEQUENTIAL_INFERENCE_MSG.format(var=var),
                        severity="error",
                    ))
    return diags


def _ruff_check(files: list[str]) -> dict[str, list[Diagnostic]]:
    """Stage 3a: ruff (preferred) — undefined names (F821), unused imports, etc.

    We surface ruff's error-class lints (F-codes, E9 syntax) as gating errors and
    everything else as non-gating warnings, mirroring opencode treating LSP
    `error` severity as actionable and lower severities as informational.
    """
    result: dict[str, list[Diagnostic]] = {}
    try:
        proc = subprocess.run(
            ["ruff", "check", "--output-format=concise", "--no-cache", *files],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return result
    # concise format: path:line:col: CODE message
    for raw in proc.stdout.splitlines():
        parts = raw.split(":", 3)
        if len(parts) < 4:
            continue
        fpath, line_s, col_s, rest = parts
        rest = rest.strip()
        code = rest.split(" ", 1)[0] if rest else ""
        # F8xx (undefined/unused), E9xx (syntax), F4xx (import) → errors; rest → warnings
        gating = code.startswith(("F8", "E9", "F4", "F6"))
        sev = "error" if gating else "warning"
        try:
            line = int(line_s)
            col = int(col_s)
        except ValueError:
            line, col = 0, 0
        result.setdefault(fpath, []).append(Diagnostic(line, col, rest, sev))
    return result


def _pyflakes_check(files: list[str]) -> dict[str, list[Diagnostic]]:
    """Stage 3b: pyflakes fallback when ruff is absent."""
    result: dict[str, list[Diagnostic]] = {}
    try:
        proc = subprocess.run(
            ["pyflakes", *files], capture_output=True, text=True, timeout=60
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return result
    for raw in (proc.stdout + "\n" + proc.stderr).splitlines():
        parts = raw.split(":", 3)
        if len(parts) < 3:
            continue
        # pyflakes emits either `path:line: msg` or `path:line:col: msg`
        fpath, line_s = parts[0], parts[1]
        if len(parts) == 4 and parts[2].strip().isdigit():
            col_s, msg = parts[2], parts[3]
        else:
            col_s, msg = "0", ":".join(parts[2:])
        try:
            line, col = int(line_s), int(col_s)
        except ValueError:
            line, col = 0, 0
        result.setdefault(fpath, []).append(Diagnostic(line, col, msg.strip(), "error"))
    return result


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2

    files = _collect_py_files(argv)
    if not files:
        print("static_gate: no python files found to check", file=sys.stderr)
        return 2

    # Per-file syntax + compile (stdlib, always available)
    diags: dict[str, list[Diagnostic]] = {f: [] for f in files}
    syntax_broken: set[str] = set()
    for f in files:
        try:
            with open(f, encoding="utf-8") as fh:
                source = fh.read()
        except (OSError, UnicodeDecodeError) as e:
            diags[f].append(Diagnostic(0, 0, f"cannot read file: {e}"))
            syntax_broken.add(f)
            continue
        syn = _syntax_check(f, source)
        if syn:
            diags[f].extend(syn)
            syntax_broken.add(f)
            continue
        diags[f].extend(_compile_check(f))
        # #13 perf gate: per-example generate() in a loop → sequential inference.
        diags[f].extend(_sequential_inference_check(f, source))

    # Linter pass — only on files that at least parse (linters choke on broken syntax)
    lintable = [f for f in files if f not in syntax_broken]
    linter = "ruff" if shutil.which("ruff") else ("pyflakes" if shutil.which("pyflakes") else None)
    if lintable:
        if linter == "ruff":
            for f, ds in _ruff_check(lintable).items():
                diags.setdefault(f, []).extend(ds)
        elif linter == "pyflakes":
            for f, ds in _pyflakes_check(lintable).items():
                diags.setdefault(f, []).extend(ds)

    # Report
    total_errors = 0
    total_warnings = 0
    blocks: list[str] = []
    for f in files:
        ds = diags.get(f, [])
        # match diagnostics keyed by realpath vs given path from linters
        for alt in list(diags.keys()):
            if alt != f and os.path.realpath(alt) == os.path.realpath(f):
                ds = ds + diags[alt]
        errs = [d for d in ds if d.severity == "error"]
        warns = [d for d in ds if d.severity == "warning"]
        total_errors += len(errs)
        total_warnings += len(warns)
        shown = (errs + warns)[:MAX_PER_FILE]
        if shown:
            extra = len(errs) + len(warns) - len(shown)
            lines = [d.render() for d in shown]
            if extra > 0:
                lines.append(f"  ... and {extra} more")
            blocks.append(f"{f}\n" + "\n".join(lines))

    if total_errors == 0 and total_warnings == 0:
        print(f"static_gate: OK — {len(files)} file(s) clean "
              f"(linter: {linter or 'none — install ruff for undefined-name checks'})")
        return 0

    print(f"STATIC ERRORS detected — fix before push "
          f"({total_errors} error(s), {total_warnings} warning(s); linter: {linter or 'none'}):\n")
    print("\n\n".join(blocks))
    if total_errors == 0:
        print("\nstatic_gate: warnings only — push not blocked.")
        return 0
    print("\nstatic_gate: BLOCKED. Fix every [error] above, then re-run this gate. "
          "Do not push code that fails the gate (Stage 6a critic auto-REJECTs).")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

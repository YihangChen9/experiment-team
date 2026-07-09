#!/usr/bin/env python3
"""result-figures renderer — standard Stage-7 result figures from a JSON spec.

The Stage-7 analyst should NOT hand-write matplotlib each run (agent-generated
plotting code varies wildly run to run — the same lesson as run 2a8935af8c61's
improvised resume manifest). Instead: write a small JSON spec containing ONLY
numbers that already appear in the report's tables, then render with this CLI.

Usage:
    plot.py SPEC.json -o OUTPUT_DIR

Spec format (JSON):
{
  "figures": [
    {
      "type": "bar",                          # bar | grouped_bar | matrix2x2 | box | line
      "filename": "stage7_fig1_primary.png",  # MUST match stage7_*.png for paper embed
      "caption": "Primary outcome per condition with 95% CI.",
      "title": "GSM8K test split (n=1,319)",
      "ylabel": "Accuracy (%)",
      ...type-specific fields below...
    }
  ]
}

Type-specific fields:
  bar:         labels:[...], values:[...], ci:[[lo,hi],...] (optional, absolute bounds)
  grouped_bar: groups:[...], series:[{label, values, ci?}, ...]
  matrix2x2:   cells:[[a,b],[c,d]], xlabel_pair:["X correct","X incorrect"],
               ylabel_pair:["Y correct","Y incorrect"]   (counts heatmap, annotated)
  box:         labels:[...], samples:[[...],[...]]        (raw per-seed values)
  line:        x:[...], series:[{label, y, band?:[[lo,hi],...]}, ...], xlabel

On success prints, for each figure, the exact markdown embed line to paste
into stage7_result_analyst.md:
    ![Figure N: <caption>](<filename>)

Exit codes: 0 ok; 2 spec invalid (message names the offending field).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

_COLORS = ["#4878a8", "#5aa469", "#b0b0b0", "#c46d5e", "#8d6cab", "#c9a227"]


class SpecError(ValueError):
    pass


def _req(fig: dict, key: str, fig_idx: int):
    if key not in fig:
        raise SpecError(f"figures[{fig_idx}]: missing required field '{key}'")
    return fig[key]


def _ci_to_err(values: list[float], ci: list[list[float]]) -> np.ndarray:
    lo = [v - c[0] for v, c in zip(values, ci)]
    hi = [c[1] - v for v, c in zip(values, ci)]
    if any(x < 0 for x in lo + hi):
        raise SpecError("ci bounds must bracket the value (lo <= value <= hi)")
    return np.array([lo, hi])


def _render_bar(fig: dict, ax, idx: int):
    labels = _req(fig, "labels", idx)
    values = _req(fig, "values", idx)
    if len(labels) != len(values):
        raise SpecError(f"figures[{idx}]: labels/values length mismatch")
    err = _ci_to_err(values, fig["ci"]) if fig.get("ci") else None
    ax.bar(labels, values, yerr=err, capsize=5,
           color=_COLORS[: len(values)], edgecolor="black", linewidth=0.5)
    ax.set_ylim(bottom=0)


def _render_grouped_bar(fig: dict, ax, idx: int):
    groups = _req(fig, "groups", idx)
    series = _req(fig, "series", idx)
    n, w = len(series), 0.8 / max(len(series), 1)
    x = np.arange(len(groups))
    for si, s in enumerate(series):
        vals = s["values"]
        if len(vals) != len(groups):
            raise SpecError(f"figures[{idx}]: series '{s.get('label')}' length mismatch")
        err = _ci_to_err(vals, s["ci"]) if s.get("ci") else None
        ax.bar(x + (si - (n - 1) / 2) * w, vals, w, yerr=err, capsize=3,
               label=s.get("label", f"series {si}"), color=_COLORS[si % len(_COLORS)],
               edgecolor="black", linewidth=0.5)
    ax.set_xticks(x, groups)
    ax.legend(frameon=False, fontsize=8)
    ax.set_ylim(bottom=0)


def _render_matrix2x2(fig: dict, ax, idx: int):
    cells = np.array(_req(fig, "cells", idx), dtype=float)
    if cells.shape != (2, 2):
        raise SpecError(f"figures[{idx}]: cells must be 2x2")
    im = ax.imshow(cells, cmap="Blues")
    for (r, c), v in np.ndenumerate(cells):
        ax.text(c, r, f"{int(v):,}", ha="center", va="center",
                color="white" if v > cells.max() / 2 else "black", fontsize=12)
    xp = fig.get("xlabel_pair", ["positive", "negative"])
    yp = fig.get("ylabel_pair", ["positive", "negative"])
    ax.set_xticks([0, 1], xp, fontsize=8)
    ax.set_yticks([0, 1], yp, fontsize=8)
    plt.colorbar(im, ax=ax, fraction=0.046)


def _render_box(fig: dict, ax, idx: int):
    labels = _req(fig, "labels", idx)
    samples = _req(fig, "samples", idx)
    if len(labels) != len(samples):
        raise SpecError(f"figures[{idx}]: labels/samples length mismatch")
    ax.boxplot(samples, tick_labels=labels, showmeans=True)
    for i, vals in enumerate(samples, start=1):
        jitter = (np.random.default_rng(7).random(len(vals)) - 0.5) * 0.15
        ax.plot(np.full(len(vals), i) + jitter, vals, "o",
                color=_COLORS[(i - 1) % len(_COLORS)], alpha=0.6, markersize=4)


def _render_line(fig: dict, ax, idx: int):
    x = _req(fig, "x", idx)
    series = _req(fig, "series", idx)
    for si, s in enumerate(series):
        y = s["y"]
        if len(y) != len(x):
            raise SpecError(f"figures[{idx}]: series '{s.get('label')}' length mismatch")
        ax.plot(x, y, "-o", markersize=3, label=s.get("label", f"series {si}"),
                color=_COLORS[si % len(_COLORS)])
        if s.get("band"):
            lo = [b[0] for b in s["band"]]
            hi = [b[1] for b in s["band"]]
            ax.fill_between(x, lo, hi, alpha=0.15, color=_COLORS[si % len(_COLORS)])
    ax.set_xlabel(fig.get("xlabel", ""))
    ax.legend(frameon=False, fontsize=8)


_RENDERERS = {
    "bar": _render_bar,
    "grouped_bar": _render_grouped_bar,
    "matrix2x2": _render_matrix2x2,
    "box": _render_box,
    "line": _render_line,
}


def render(spec: dict, outdir: Path) -> list[tuple[str, str]]:
    """Render every figure in the spec. Returns [(filename, caption)]."""
    figures = spec.get("figures")
    if not isinstance(figures, list) or not figures:
        raise SpecError("spec must contain a non-empty 'figures' array")
    out: list[tuple[str, str]] = []
    for idx, f in enumerate(figures):
        ftype = _req(f, "type", idx)
        if ftype not in _RENDERERS:
            raise SpecError(
                f"figures[{idx}]: unknown type '{ftype}' (valid: {sorted(_RENDERERS)})")
        filename = _req(f, "filename", idx)
        if not filename.startswith("stage7_") or not filename.endswith(".png"):
            raise SpecError(
                f"figures[{idx}]: filename must match stage7_*.png "
                f"(the Stage-8 paper-writer's embed glob), got '{filename}'")
        caption = _req(f, "caption", idx)
        fig_obj, ax = plt.subplots(figsize=tuple(f.get("figsize", (5.2, 3.4))))
        _RENDERERS[ftype](f, ax, idx)
        if f.get("title"):
            ax.set_title(f["title"], fontsize=10)
        if f.get("ylabel"):
            ax.set_ylabel(f["ylabel"])
        fig_obj.tight_layout()
        outdir.mkdir(parents=True, exist_ok=True)
        path = outdir / filename
        fig_obj.savefig(path, dpi=150)
        plt.close(fig_obj)
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f"render produced no file for {filename}")
        out.append((filename, caption))
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("spec", help="path to the JSON spec")
    ap.add_argument("-o", "--outdir", default=".", help="output directory (project workspace)")
    args = ap.parse_args(argv)
    try:
        spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"SPEC ERROR: cannot read spec: {e}", file=sys.stderr)
        return 2
    try:
        rendered = render(spec, Path(args.outdir))
    except SpecError as e:
        print(f"SPEC ERROR: {e}", file=sys.stderr)
        return 2
    print(f"rendered {len(rendered)} figure(s) -> {args.outdir}")
    print("--- paste these embed lines into stage7_result_analyst.md ---")
    for n, (filename, caption) in enumerate(rendered, start=1):
        print(f"![Figure {n}: {caption}]({filename})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

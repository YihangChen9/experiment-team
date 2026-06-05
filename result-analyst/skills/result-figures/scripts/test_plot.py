"""Contract tests for the result-figures renderer.

Run with the engine repo's venv (pytest only — matplotlib lives in the
throwaway venv that bootstrap.sh builds):

    .venv/bin/python -m pytest <this file> -q

The tests exercise the REAL CLI through bootstrap.sh, so they also verify
the venv bootstrap path the Stage-7 analyst will actually use.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent
BOOTSTRAP = SCRIPTS / "bootstrap.sh"


def _run(spec: dict, outdir: Path) -> subprocess.CompletedProcess:
    spec_path = outdir / "spec.json"
    outdir.mkdir(parents=True, exist_ok=True)
    spec_path.write_text(json.dumps(spec), encoding="utf-8")
    return subprocess.run(
        ["bash", str(BOOTSTRAP), str(spec_path), "-o", str(outdir)],
        capture_output=True, text=True, timeout=180,
    )


@pytest.fixture(scope="module")
def all_types_result(tmp_path_factory):
    outdir = tmp_path_factory.mktemp("figs")
    spec = {"figures": [
        {"type": "bar", "filename": "stage7_fig1_primary.png",
         "caption": "Primary outcome per condition with 95% CI.",
         "title": "GSM8K test split (n=1,319)", "ylabel": "Accuracy (%)",
         "labels": ["Direct-512", "CoT-512", "Direct-16"],
         "values": [16.38, 85.97, 16.45],
         "ci": [[14.4, 18.4], [84.0, 87.8], [14.5, 18.5]]},
        {"type": "grouped_bar", "filename": "stage7_fig2_grouped.png",
         "caption": "Outcome per benchmark and method.", "ylabel": "Regret",
         "groups": ["Currin", "Branin"],
         "series": [{"label": "cascade_voi", "values": [5.3, 2.1]},
                    {"label": "mf_gp_ucb", "values": [7.9, 3.3]}]},
        {"type": "matrix2x2", "filename": "stage7_fig3_mcnemar.png",
         "caption": "Discordant-pair matrix (McNemar).",
         "cells": [[200, 934], [16, 169]],
         "xlabel_pair": ["CoT correct", "CoT incorrect"],
         "ylabel_pair": ["Direct correct", "Direct incorrect"]},
        {"type": "box", "filename": "stage7_fig4_box.png",
         "caption": "Per-seed regret per method.", "ylabel": "Simple regret",
         "labels": ["cascade", "baseline"],
         "samples": [[5.1, 4.7, 6.0, 5.5], [8.2, 7.4, 9.1, 8.8]]},
        {"type": "line", "filename": "stage7_fig5_curve.png",
         "caption": "Regret vs budget.", "ylabel": "Regret", "xlabel": "Budget",
         "x": [10, 20, 30, 40],
         "series": [{"label": "cascade", "y": [9, 7, 6, 5.3],
                     "band": [[8, 10], [6, 8], [5, 7], [4.8, 5.9]]}]},
    ]}
    return outdir, _run(spec, outdir)


def test_all_five_types_render(all_types_result):
    outdir, proc = all_types_result
    assert proc.returncode == 0, proc.stderr
    for i in range(1, 6):
        matches = list(outdir.glob(f"stage7_fig{i}_*.png"))
        assert matches and matches[0].stat().st_size > 1000, f"fig{i} missing/empty"


def test_embed_lines_printed_in_paper_writer_format(all_types_result):
    _, proc = all_types_result
    lines = [l for l in proc.stdout.splitlines() if l.startswith("![Figure")]
    assert len(lines) == 5
    assert lines[0] == ("![Figure 1: Primary outcome per condition with 95% CI.]"
                        "(stage7_fig1_primary.png)")


def test_bad_filename_rejected(tmp_path):
    proc = _run({"figures": [{"type": "bar", "filename": "results.png",
                              "caption": "x", "labels": ["a"], "values": [1]}]},
                tmp_path)
    assert proc.returncode == 2
    assert "stage7_*.png" in proc.stderr


def test_unknown_type_rejected(tmp_path):
    proc = _run({"figures": [{"type": "pie", "filename": "stage7_fig1_x.png",
                              "caption": "x"}]}, tmp_path)
    assert proc.returncode == 2
    assert "unknown type" in proc.stderr


def test_ci_must_bracket_value(tmp_path):
    proc = _run({"figures": [{"type": "bar", "filename": "stage7_fig1_x.png",
                              "caption": "x", "labels": ["a"], "values": [5.0],
                              "ci": [[6.0, 7.0]]}]}, tmp_path)
    assert proc.returncode == 2
    assert "bracket" in proc.stderr

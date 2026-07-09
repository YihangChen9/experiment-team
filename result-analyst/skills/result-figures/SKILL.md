---
name: result-figures
description: Render standard Stage-7 result figures (bar with CI error bars, grouped bar, McNemar 2x2 matrix, per-method box, line/curve with confidence band) from a small JSON spec — no hand-written matplotlib. Use during Stage 7 result analysis whenever numeric confirmatory results exist.
allowed-tools: Bash, Read, Write
---

# result-figures — standard result plots from a JSON spec

Do **NOT** hand-write matplotlib in Stage 7. Agent-generated plotting
code varies run to run (same failure class as run 2a8935af8c61's
improvised resume manifest); this skill ships a tested renderer with
the standard figure types built in. You supply ONLY the numbers — and
only numbers that already appear in your report's tables.

## Usage (two steps)

1. Write a spec JSON into the project workspace, e.g. `stage7_figs.json`:

```json
{
  "figures": [
    {
      "type": "bar",
      "filename": "stage7_fig1_primary_outcome.png",
      "caption": "Primary outcome per condition with 95% CI.",
      "title": "GSM8K test split (n=1,319)",
      "ylabel": "Accuracy (%)",
      "labels": ["Direct-512", "CoT-512", "Direct-16"],
      "values": [16.38, 85.97, 16.45],
      "ci": [[14.4, 18.4], [84.0, 87.8], [14.5, 18.5]]
    },
    {
      "type": "matrix2x2",
      "filename": "stage7_fig2_discordant.png",
      "caption": "Discordant-pair matrix (McNemar).",
      "cells": [[200, 934], [16, 169]],
      "xlabel_pair": ["CoT correct", "CoT incorrect"],
      "ylabel_pair": ["Direct correct", "Direct incorrect"]
    }
  ]
}
```

2. Render into the project workspace:

```bash
bash "$SKILL_DIR/scripts/bootstrap.sh" <project_workspace>/stage7_figs.json -o <project_workspace>
```

`bootstrap.sh` builds a throwaway uv venv with matplotlib on first use
(seconds; never touches the project env) and runs `plot.py`. On success
it prints the exact markdown embed lines — **paste them into
`stage7_result_analyst.md` at the point where the numbers are
discussed**:

```
![Figure 1: Primary outcome per condition with 95% CI.](stage7_fig1_primary_outcome.png)
```

## Figure types

| type | required fields | use for |
|---|---|---|
| `bar` | `labels`, `values`, optional `ci` `[[lo,hi],…]` | primary outcome per condition (the default first figure) |
| `grouped_bar` | `groups`, `series:[{label, values, ci?}]` | condition × method grids |
| `matrix2x2` | `cells:[[a,b],[c,d]]`, `xlabel_pair`, `ylabel_pair` | McNemar discordant pairs |
| `box` | `labels`, `samples:[[…],…]` (raw per-seed values) | per-method distributions |
| `line` | `x`, `series:[{label, y, band?}]`, `xlabel` | regret-vs-budget / learning curves |

Common fields: `filename` (**MUST match `stage7_*.png`** — that is the
glob Stage 8's paper-writer auto-embeds), `caption`, optional `title`,
`ylabel`, `figsize`.

## Hard rules

- Figures visualise numbers **already in your report's tables** —
  a figure is a view of the confirmatory data, never a new analysis.
- `ci` bounds are absolute `[lo, hi]` and must bracket the value
  (the renderer rejects inverted bounds — exit 2 with the field named).
- One spec, one render call, all figures — don't loop the CLI.
- If `uv` is missing or pip has no network, record the failure verbatim
  in §8 Limitations of your report; do not silently skip figures.

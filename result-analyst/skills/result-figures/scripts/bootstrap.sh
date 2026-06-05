#!/usr/bin/env bash
# bootstrap.sh — ensure a plotting venv exists, then run plot.py through it.
#
# Usage:  bootstrap.sh SPEC.json -o OUTPUT_DIR
#
# The host python frequently lacks (or has a broken) matplotlib; a throwaway
# uv venv is seconds with a warm cache and never touches the project env.
set -euo pipefail

VENV="${RESULT_FIGURES_VENV:-/tmp/stage7_plots}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$VENV/bin/python" ]; then
  uv venv "$VENV" --python 3.12 2>/dev/null || uv venv "$VENV"
fi
"$VENV/bin/python" -c "import matplotlib, numpy" 2>/dev/null || \
  uv pip install --python "$VENV/bin/python" --quiet matplotlib numpy

exec "$VENV/bin/python" "$SCRIPT_DIR/plot.py" "$@"

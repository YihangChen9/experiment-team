#!/usr/bin/env bash
# Usage:
#   ./fast_query_exp_status.sh [flags] [RUN_ID]
# Flags:
#   --url URL | -u URL          override INFRA_SERVER_URL for this run
#   --key KEY | -k KEY          override INFRA_SESSION_KEY for this run
#   --save | --no-save | -n     save to infra_query_logs/ (default) vs stdout only
#   --with-budget              also fetch /api/budget before /api/list_runs
#   --runs-only | -r            deprecated no-op; list_runs is the default with no RUN_ID
#   --summary                   drop log_tail from each run (lighter JSON / tables)
#   RUN_ID                      /api/status for that run (--summary strips log_tail)
#
#   INFRA_SERVER_URL, INFRA_SESSION_KEY — required from env and/or --url / --key.
#   INFRA_QUERY_LOG_DIR overrides the save directory when saving.
#   INFRA_LIST_LIMIT caps list_runs (API max 100; default 100).

set -euo pipefail

_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$_SCRIPTS_DIR/.." && pwd)"
INFRA_REPO_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
OUT_DIR="${INFRA_QUERY_LOG_DIR:-$INFRA_REPO_ROOT/infra_query_logs}"

URL="${INFRA_SERVER_URL:-}"
KEY="${INFRA_SESSION_KEY:-}"
SAVE=true
WITH_BUDGET=false
SUMMARY=false
POS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-save|-n) SAVE=false; shift ;;
    --save) SAVE=true; shift ;;
    --with-budget) WITH_BUDGET=true; shift ;;
    --runs-only|-r) WITH_BUDGET=false; shift ;;
    --summary) SUMMARY=true; shift ;;
    --url|-u)
      if [[ $# -lt 2 ]]; then echo "error: $1 requires a value" >&2; exit 1; fi
      URL="$2"
      shift 2
      ;;
    --key|-k)
      if [[ $# -lt 2 ]]; then echo "error: $1 requires a value" >&2; exit 1; fi
      KEY="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  ./fast_query_exp_status.sh [flags] [RUN_ID]

  --url URL | -u URL   override INFRA_SERVER_URL for this run
  --key KEY | -k KEY   override INFRA_SESSION_KEY for this run
  --save               write JSON under infra_query_logs/ (default)
  --no-save | -n       pretty-print to stdout only (no files)
  --with-budget        also fetch budget before listing experiment runs
  --runs-only | -r     deprecated no-op; list_runs is the default with no RUN_ID
  --summary            omit log_tail from each run (status summary without log text)

  RUN_ID               if set: /api/status for that run (--summary omits log_tail there too)

  INFRA_SERVER_URL     base URL (required unless --url)
  INFRA_SESSION_KEY    session key (required unless --key)

  INFRA_QUERY_LOG_DIR overrides the save directory when saving.
  INFRA_LIST_LIMIT    list_runs limit (API max 100; default 100).
EOF
      exit 0
      ;;
    *)
      POS+=("$1")
      shift
      ;;
  esac
done

RUN_ID="${POS[0]:-}"
if [[ ${#POS[@]} -gt 1 ]]; then
  echo "error: unexpected extra arguments:" "${POS[@]:1}" >&2
  exit 1
fi

if [[ -z "$URL" ]]; then
  echo "error: remote API URL is required (set INFRA_SERVER_URL or pass --url URL)" >&2
  exit 1
fi
if [[ -z "$KEY" ]]; then
  echo "error: session key is required (set INFRA_SESSION_KEY or pass --key KEY)" >&2
  exit 1
fi

while [[ "$URL" == */ ]]; do URL="${URL%/}"; done
LIST_LIMIT="${INFRA_LIST_LIMIT:-100}"
TS=$(date -u +"%Y%m%dT%H%M%SZ")

if [[ "$SAVE" == true ]]; then
  mkdir -p "$OUT_DIR"
fi

pretty_json() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    python3 -m json.tool
  fi
}

# Strip log_tail from JSON on stdin. Pass first arg "true" to strip, anything else to pass through.
# Handles /api/list_runs (top-level "runs" array) and /api/status (single run object).
strip_log_tail_json() {
  local do_strip="$1"
  if [[ "$do_strip" != true ]]; then
    cat
    return
  fi
  python3 -c '
import json, sys
d = json.load(sys.stdin)
runs = d.get("runs")
if isinstance(runs, list):
    for r in runs:
        if isinstance(r, dict):
            r.pop("log_tail", None)
elif isinstance(d, dict) and "run_id" in d:
    d.pop("log_tail", None)
json.dump(d, sys.stdout)
sys.stdout.write("\n")
'
}

emit_response() {
  local dest="$1"
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  cat >"$tmp"
  if [[ "$SAVE" == true ]]; then
    pretty_json <"$tmp" | tee "$dest"
    printf 'Saved %s\n' "$dest" >&2
  else
    pretty_json <"$tmp"
  fi
}

fetch_list_runs() {
  local dest="$1"
  curl -sS -X POST "$URL/api/list_runs" -H "Content-Type: application/json" \
    -d "{\"session_key\":\"$KEY\",\"limit\":$LIST_LIMIT}" \
    | strip_log_tail_json "$SUMMARY" | emit_response "$dest"
}

if [[ -n "$RUN_ID" ]]; then
  curl -sS -X POST "$URL/api/status" -H "Content-Type: application/json" \
    -d "{\"session_key\":\"$KEY\",\"run_id\":\"$RUN_ID\"}" \
    | strip_log_tail_json "$SUMMARY" | emit_response "$OUT_DIR/status_${RUN_ID}_${TS}.json"
  exit 0
fi

if [[ "$WITH_BUDGET" == true ]]; then
  curl -sS -X POST "$URL/api/budget" -H "Content-Type: application/json" \
    -d "{\"session_key\":\"$KEY\"}" | emit_response "$OUT_DIR/budget_${TS}.json"
fi

suffix="list_runs_${TS}.json"
[[ "$SUMMARY" == true ]] && suffix="list_runs_summary_${TS}.json"
fetch_list_runs "$OUT_DIR/$suffix"

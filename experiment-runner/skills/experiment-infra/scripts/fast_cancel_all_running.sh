#!/usr/bin/env bash
# Cancel all active runs for the current user/project.
#
# Usage:
#   ./fast_cancel_all_running.sh [--url URL | -u URL] [--key KEY | -k KEY] [flags]
#
# Flags:
#   --limit N                 max recent runs to inspect through /api/list_runs (default: INFRA_LIST_LIMIT or 100)
#   --statuses CSV            statuses to cancel (default: pending,running)
#   --yes | -y                skip the confirmation prompt
#   --dry-run                 list matching run IDs without cancelling
#   --url URL | -u URL        override INFRA_SERVER_URL for this run
#   --key KEY | -k KEY        override INFRA_SESSION_KEY for this run
#
#   INFRA_SERVER_URL          base URL (required unless --url)
#   INFRA_SESSION_KEY         session key (required unless --key)
set -euo pipefail

URL="${INFRA_SERVER_URL:-}"
KEY="${INFRA_SESSION_KEY:-}"
LIMIT="${INFRA_LIST_LIMIT:-100}"
STATUSES="pending,running"
ASSUME_YES=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./fast_cancel_all_running.sh [--url URL | -u URL] [--key KEY | -k KEY] [flags]

Fetch recent runs for the current user/project, select runs whose status matches
--statuses, and cancel each selected run through POST /api/cancel.

Flags:
  --limit N          max recent runs to inspect through /api/list_runs (default: INFRA_LIST_LIMIT or 100)
  --statuses CSV     statuses to cancel (default: pending,running)
  --yes | -y         skip the confirmation prompt
  --dry-run          list matching run IDs without cancelling
  --url URL | -u URL override INFRA_SERVER_URL for this run
  --key KEY | -k KEY override INFRA_SESSION_KEY for this run

Env: INFRA_SERVER_URL, INFRA_SESSION_KEY (or pass --url / --key)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      if [[ $# -lt 2 ]]; then echo "error: $1 requires a value" >&2; exit 1; fi
      LIMIT="$2"
      shift 2
      ;;
    --statuses)
      if [[ $# -lt 2 ]]; then echo "error: $1 requires a value" >&2; exit 1; fi
      STATUSES="$2"
      shift 2
      ;;
    --yes|-y)
      ASSUME_YES=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
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
      usage
      exit 0
      ;;
    *)
      echo "error: unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$URL" ]]; then
  echo "error: remote API URL is required (set INFRA_SERVER_URL or pass --url URL)" >&2
  exit 1
fi
if [[ -z "$KEY" ]]; then
  echo "error: session key is required (set INFRA_SESSION_KEY or pass --key KEY)" >&2
  exit 1
fi
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -lt 1 ]]; then
  echo "error: --limit must be a positive integer, got $LIMIT" >&2
  exit 1
fi
if [[ -z "$STATUSES" ]]; then
  echo "error: --statuses must not be empty" >&2
  exit 1
fi

while [[ "$URL" == */ ]]; do URL="${URL%/}"; done

pretty_json() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    python3 -m json.tool
  fi
}

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

LIST_TMP="$(mktemp)"
MATCH_TMP="$(mktemp)"
CANCEL_TMP="$(mktemp)"
trap 'rm -f "$LIST_TMP" "$MATCH_TMP" "$CANCEL_TMP"' EXIT

curl -sS -X POST "$URL/api/list_runs" -H "Content-Type: application/json" \
  -d "{\"session_key\":$(json_escape "$KEY"),\"limit\":$LIMIT}" >"$LIST_TMP"

python3 - "$STATUSES" "$LIST_TMP" >"$MATCH_TMP" <<'PY'
import json
import sys

wanted = {s.strip().lower() for s in sys.argv[1].split(",") if s.strip()}
with open(sys.argv[2], encoding="utf-8") as f:
    data = json.load(f)

if data.get("error"):
    print(f"error: {data['error']}", file=sys.stderr)
    sys.exit(2)

runs = data.get("runs")
if not isinstance(runs, list):
    print("error: /api/list_runs response did not include a runs array", file=sys.stderr)
    sys.exit(2)

for run in runs:
    if not isinstance(run, dict):
        continue
    status = str(run.get("status", "")).lower()
    run_id = str(run.get("run_id", ""))
    if run_id and status in wanted:
        created_at = run.get("created_at", "")
        cluster_name = run.get("cluster_name", "")
        print("\t".join([run_id, status, str(created_at), str(cluster_name)]))
PY

MATCH_COUNT="$(wc -l <"$MATCH_TMP" | tr -d '[:space:]')"
if [[ "$MATCH_COUNT" == "0" ]]; then
  echo "No runs found with status in: $STATUSES"
  exit 0
fi

echo "Runs selected for cancellation (run_id status created_at cluster_name):"
cat "$MATCH_TMP"

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run only; no runs cancelled."
  exit 0
fi

if [[ "$ASSUME_YES" != true ]]; then
  if [[ ! -t 0 ]]; then
    echo "error: refusing to cancel without --yes because stdin is not interactive" >&2
    exit 1
  fi
  printf 'Cancel %s run(s)? Type "yes" to continue: ' "$MATCH_COUNT" >&2
  read -r CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Cancelled by user."
    exit 1
  fi
fi

SUCCESS=0
FAILED=0
>"$CANCEL_TMP"

while IFS=$'\t' read -r RUN_ID STATUS CREATED_AT CLUSTER_NAME; do
  [[ -n "$RUN_ID" ]] || continue
  RESP="$(curl -sS -X POST "$URL/api/cancel" -H "Content-Type: application/json" \
    -d "{\"session_key\":$(json_escape "$KEY"),\"run_id\":$(json_escape "$RUN_ID")}")"
  printf '%s\n' "$RESP" >"$CANCEL_TMP"
  if python3 -c 'import json, sys; sys.exit(0 if json.load(sys.stdin).get("success") is True else 1)' <"$CANCEL_TMP"; then
    SUCCESS=$((SUCCESS + 1))
    printf 'cancelled %s (%s)\n' "$RUN_ID" "$STATUS"
  else
    FAILED=$((FAILED + 1))
    printf 'failed %s (%s): ' "$RUN_ID" "$STATUS" >&2
    pretty_json <"$CANCEL_TMP" >&2
  fi
done <"$MATCH_TMP"

printf 'Done. cancelled=%s failed=%s selected=%s\n' "$SUCCESS" "$FAILED" "$MATCH_COUNT"
if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi

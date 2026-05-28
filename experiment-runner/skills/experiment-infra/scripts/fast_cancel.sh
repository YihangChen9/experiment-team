#!/usr/bin/env bash
# POST /api/cancel — bash equivalent of InfraClient.cancel(run_id).
#
# Usage:
#   ./fast_cancel.sh [--url URL | -u URL] [--key KEY | -k KEY] RUN_ID
#
#   INFRA_SERVER_URL     base URL (required unless --url)
#   INFRA_SESSION_KEY    session key (required unless --key)
#   CLI flags override environment for that run.
set -euo pipefail

URL="${INFRA_SERVER_URL:-}"
KEY="${INFRA_SESSION_KEY:-}"
RUN_ID=""

usage() {
  cat <<'EOF'
Usage: ./fast_cancel.sh [--url URL | -u URL] [--key KEY | -k KEY] RUN_ID

POST /api/cancel for the current session. Fails if the run is already
succeeded, failed, or cancelled.

Env: INFRA_SERVER_URL, INFRA_SESSION_KEY (or pass --url / --key)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
      if [[ -n "$RUN_ID" ]]; then
        echo "error: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      RUN_ID="$1"
      shift
      ;;
  esac
done

if [[ -z "$RUN_ID" ]]; then
  echo "error: RUN_ID is required" >&2
  usage >&2
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

pretty_json() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    python3 -m json.tool
  fi
}

curl -sS -X POST "$URL/api/cancel" -H "Content-Type: application/json" \
  -d "{\"session_key\":\"$KEY\",\"run_id\":\"$RUN_ID\"}" | pretty_json

#!/usr/bin/env bash
# Fast query: session / project / user budget only (POST /api/budget).
#
# Usage:
#   ./fast_query_budget.sh [--url URL | -u URL] [--key KEY | -k KEY] [--save | --no-save | -n]
#
#   URL and key are required — from flags (above) and/or environment:
#     INFRA_SERVER_URL     base URL, no trailing slash required
#     INFRA_SESSION_KEY    session key
#   CLI flags override environment for that run.
#
#   INFRA_QUERY_LOG_DIR  when saving, output directory (default: ./infra_query_logs)
set -euo pipefail

_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$_SCRIPTS_DIR/.." && pwd)"
INFRA_REPO_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
OUT_DIR="${INFRA_QUERY_LOG_DIR:-$INFRA_REPO_ROOT/infra_query_logs}"

URL="${INFRA_SERVER_URL:-}"
KEY="${INFRA_SESSION_KEY:-}"
SAVE=true

usage() {
  awk 'NR < 2 { next } /^set[[:space:]]/ { exit } { print }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-save|-n) SAVE=false; shift ;;
    --save) SAVE=true; shift ;;
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
      echo "Unknown option: $1" >&2
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

while [[ "$URL" == */ ]]; do URL="${URL%/}"; done

TS=$(date -u +"%Y%m%dT%H%M%SZ")

pretty_json() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    python3 -m json.tool
  fi
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -sS -X POST "$URL/api/budget" -H "Content-Type: application/json" \
  -d "{\"session_key\":\"$KEY\"}" >"$tmp"

if [[ "$SAVE" == true ]]; then
  mkdir -p "$OUT_DIR"
  dest="$OUT_DIR/budget_${TS}.json"
  pretty_json <"$tmp" | tee "$dest"
  printf 'Saved %s\n' "$dest" >&2
else
  pretty_json <"$tmp"
fi

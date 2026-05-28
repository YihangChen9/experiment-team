#!/usr/bin/env bash
# Fast query: tree snapshot of the session remote working directory (POST /api/working_dir_tree).
#
# Usage:
#   ./fast_query_working_dir.sh [--url URL | -u URL] [--key KEY | -k KEY] [MAX_DEPTH] [--max-depth N] [--save | --no-save | -n]
#
#   URL and key are required — from flags and/or environment:
#     INFRA_SERVER_URL     base URL, no trailing slash required
#     INFRA_SESSION_KEY    session key
#   CLI flags override environment for that run.
#
#   MAX_DEPTH                         optional first positional (non-negative integer)
#   --max-depth N                     same (overrides positional if both given after parse order)
#   INFRA_QUERY_LOG_DIR               when saving, output directory (default: under infra repo root)
#   INFRA_WORKING_DIR_TREE_MAX_DEPTH  default depth when no positional/--max-depth (default: 4)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_REPO_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
OUT_DIR="${INFRA_QUERY_LOG_DIR:-$INFRA_REPO_ROOT/infra_query_logs}"

URL="${INFRA_SERVER_URL:-}"
KEY="${INFRA_SESSION_KEY:-}"
SAVE=true
MAX_DEPTH="${INFRA_WORKING_DIR_TREE_MAX_DEPTH:-4}"
POS_DEPTH=""
MAX_DEPTH_FROM_FLAG=false

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
    --max-depth)
      if [[ $# -lt 2 ]]; then
        echo "Usage: $0 [--url URL] [--key KEY] [--max-depth N] [MAX_DEPTH] ..." >&2
        exit 1
      fi
      MAX_DEPTH="$2"
      MAX_DEPTH_FROM_FLAG=true
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]] && [[ -z "${POS_DEPTH}" ]]; then
        POS_DEPTH="$1"
        shift
      else
        echo "Unknown option or argument: $1" >&2
        usage >&2
        exit 1
      fi
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

if [[ "${MAX_DEPTH_FROM_FLAG}" != true ]] && [[ -n "${POS_DEPTH}" ]]; then
  MAX_DEPTH="${POS_DEPTH}"
fi

if ! [[ "${MAX_DEPTH}" =~ ^[0-9]+$ ]]; then
  echo "max_depth must be a non-negative integer, got ${MAX_DEPTH}" >&2
  exit 1
fi

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

curl -sS -X POST "$URL/api/working_dir_tree" -H "Content-Type: application/json" \
  -d "{\"session_key\":\"$KEY\",\"max_depth\":${MAX_DEPTH}}" >"$tmp"

if [[ "$SAVE" == true ]]; then
  mkdir -p "$OUT_DIR"
  dest="$OUT_DIR/working_dir_tree_${TS}.json"
  pretty_json <"$tmp" | tee "$dest"
  printf 'Saved %s\n' "$dest" >&2
else
  pretty_json <"$tmp"
fi

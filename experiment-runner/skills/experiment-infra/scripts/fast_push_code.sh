#!/usr/bin/env bash
# HTTP push of a local file or directory to the Infra API (same as InfraClient.push_codebase_http).
# Remote path must be accepted by the API under the session's assigned workspace.
#
# Implementation: tar | curl — no Python / InfraClient required (optional jq or python3 only
# for URL-encoding query parameters).
#
# Usage:
#   ./fast_push_code.sh [--url URL | -u URL] [--key KEY | -k KEY] LOCAL_PATH REMOTE_DEST
#
# LOCAL_PATH and REMOTE_DEST are required (no defaults). Relative LOCAL_PATH is resolved
# from the caller's current working directory. Absolute LOCAL_PATH is recommended for
# scripted/agent use because it is unambiguous.
#
# URL and key are required — from flags and/or environment:
#   INFRA_SERVER_URL     base URL, no trailing slash required
#   INFRA_SESSION_KEY    session key
#   CLI flags override environment for that run.

set -euo pipefail

_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$_SCRIPTS_DIR/.." && pwd)"
CALLER_PWD="$(pwd)"
URL="${INFRA_SERVER_URL:-}"
KEY="${INFRA_SESSION_KEY:-}"

usage() {
  cat <<'EOF'
Usage: ./fast_push_code.sh [--url URL | -u URL] [--key KEY | -k KEY] LOCAL_PATH REMOTE_DEST

HTTP upload (gzip tar) to POST /api/push_codebase — same behavior as InfraClient.push_codebase_http.
Uses tar(1) and curl(1) only; jq or python3 is used to URL-encode query parameters if available.

REMOTE_DEST must be a path accepted by the API under the session's assigned workspace.

LOCAL_PATH and REMOTE_DEST are required. Relative LOCAL_PATH is resolved from your current
working directory. Absolute LOCAL_PATH is recommended for scripted/agent use.

Env: INFRA_SERVER_URL, INFRA_SESSION_KEY (or pass --url / --key)
EOF
}

POS=()
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
      POS+=("$1")
      shift
      ;;
  esac
done

if (( ${#POS[@]} < 2 )); then
  echo "error: LOCAL_PATH and REMOTE_DEST are required (see --help)" >&2
  exit 1
fi
LOCAL="${POS[0]}"
REMOTE="${POS[1]}"

if [[ -z "$URL" ]]; then
  echo "error: remote API URL is required (set INFRA_SERVER_URL or pass --url URL)" >&2
  exit 1
fi
if [[ -z "$KEY" ]]; then
  echo "error: session key is required (set INFRA_SESSION_KEY or pass --key KEY)" >&2
  exit 1
fi

while [[ "$URL" == */ ]]; do URL="${URL%/}"; done

if [[ "$LOCAL" != /* ]]; then
  LOCAL="$CALLER_PWD/${LOCAL#./}"
fi
if [[ -d "$LOCAL" ]]; then
  LOCAL="$(cd "$LOCAL" && pwd)"
elif [[ -f "$LOCAL" ]]; then
  LOCAL="$(cd "$(dirname "$LOCAL")" && pwd)/$(basename "$LOCAL")"
else
  echo "fast_push_code.sh: not a file or directory: $LOCAL" >&2
  exit 1
fi


pretty_json() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    python3 -m json.tool
  fi
}

uri_escape() {
  if command -v jq >/dev/null 2>&1; then
    jq -rn --arg s "$1" '$s|@uri'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse as u; print(u.quote(sys.argv[1], safe=""))' "$1"
  else
    echo "fast_push_code.sh: need jq or python3 to URL-encode query parameters" >&2
    return 1
  fi
}

stream_dir_targz() {
  local root="$1"
  tar -czf - \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='.venv' \
    --exclude='venv' \
    --exclude='*.pyc' \
    --exclude='.mypy_cache' \
    --exclude='.pytest_cache' \
    --exclude='*.egg-info' \
    --exclude='dist' \
    --exclude='build' \
    --exclude='infra_query_logs' \
    --exclude='.idea' \
    --exclude='.vscode' \
    -C "$root" .
}

stream_file_targz() {
  local local_path="$1" remote="$2" arcname base bn tmpd
  if [[ "$remote" == */ ]]; then
    arcname="$(basename "$local_path")"
  else
    arcname="$(basename "$remote")"
  fi
  base="$(dirname "$local_path")"
  bn="$(basename "$local_path")"
  if [[ "$bn" == "$arcname" ]]; then
    tar -czf - -C "$base" "$bn"
    return
  fi
  tmpd="$(mktemp -d)"
  cleanup() { rm -rf "$tmpd"; }
  trap cleanup EXIT
  cp -p "$local_path" "$tmpd/$arcname"
  tar -czf - -C "$tmpd" "$arcname"
  trap - EXIT
  cleanup
}

enc_key="$(uri_escape "$KEY")" || exit 1

if [[ -f "$LOCAL" ]]; then
  if [[ "$REMOTE" == */ ]]; then
    upload_dest="${REMOTE%/}"
  else
    upload_dest="$(dirname "$REMOTE")"
  fi
  enc_dest="$(uri_escape "$upload_dest")" || exit 1
  endpoint="${URL}/api/push_codebase?session_key=${enc_key}&remote_dest=${enc_dest}"
  stream_file_targz "$LOCAL" "$REMOTE" | curl -sS --max-time 600 -X POST "$endpoint" \
    -H 'Content-Type: application/gzip' \
    --data-binary @- | pretty_json
elif [[ -d "$LOCAL" ]]; then
  upload_dest="${REMOTE%/}"
  enc_dest="$(uri_escape "$upload_dest")" || exit 1
  endpoint="${URL}/api/push_codebase?session_key=${enc_key}&remote_dest=${enc_dest}"
  stream_dir_targz "$LOCAL" | curl -sS --max-time 600 -X POST "$endpoint" \
    -H 'Content-Type: application/gzip' \
    --data-binary @- | pretty_json
fi

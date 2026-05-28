#!/usr/bin/env bash
# POST /api/submit — bash equivalent of InfraClient.submit / submit_from_sky_yaml.
#
# Submit parameters live in a JSON config file (see examples/submit_cfg/fast_submit.conf.json).
#
# Usage:
#   ./fast_submit.sh [flags]
#
#   INFRA_SERVER_URL           base URL (required unless --url)
#   INFRA_SESSION_KEY          session key (required unless --key)
#
# Flags:
#   --url URL | -u URL         override INFRA_SERVER_URL for this run
#   --key KEY | -k KEY         override INFRA_SESSION_KEY for this run
#   --config PATH              JSON config for the experiment setup
#   --yaml PATH                override config's yaml_path for this run, yaml used for skypilot run, include more explicit setup
#   -c, --cmd COMMAND          override config's run_command for this run (non-empty = YAML ignored)
#   -h, --help

set -euo pipefail

_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$_SCRIPTS_DIR/.." && pwd)"
INFRA_REPO_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
URL="${INFRA_SERVER_URL:-}"
KEY="${INFRA_SESSION_KEY:-}"

DEFAULT_CONFIG="$SKILL_DIR/assets/base.conf.json"
CONFIG_PATH=$DEFAULT_CONFIG
YAML_OVERRIDE=""
RUN_OVERRIDE=""

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
    --config)
      CONFIG_PATH="${2:?}"
      shift 2
      ;;
    --yaml)
      YAML_OVERRIDE="${2:?}"
      shift 2
      ;;
    -c|--cmd|--run-command)
      RUN_OVERRIDE="${2:?}"
      shift 2
      ;;
    -h|--help)
      sed -n '1,26p' "$0" | tail -n +2
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
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
export INFRA_SESSION_KEY="$KEY"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Config not found: $CONFIG_PATH" >&2
  echo "Copy examples/submit_cfg/fast_submit.conf.json or set FAST_SUBMIT_CONFIG / --config" >&2
  exit 1
fi

pretty_json() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    python3 -m json.tool
  fi
}

BODY="$(python3 - "$CONFIG_PATH" "$INFRA_REPO_ROOT" "$YAML_OVERRIDE" "$RUN_OVERRIDE" <<'PY'
import json, os, subprocess, sys

CONFIG_PATH, INFRA_REPO_ROOT, yaml_override, run_override = sys.argv[1:5]

DEFAULTS = {
    "gpu": "A100:1",
    "data_version": "",
    "random_seed": 42,
    "estimated_hours": 1.0,
    "workdir": "",
    "log_dir": "",
    "run_local": False,
    "save_log_to_workdir": True,
    "use_spot": True,
    "local_use_bash": True,
    "strict_provenance": True,
    "git_commit": "",
    "dataset_s3": "",
    "output_s3": "",
    "resume_from": "",
    "cloud": "ssh",
    "config": {},
    "yaml_path": "",
    "run_command": "",
}

with open(CONFIG_PATH, encoding="utf-8") as f:
    user = json.load(f)

cfg = {**DEFAULTS, **user}

run_cmd = (run_override if run_override.strip() else cfg.get("run_command") or "").strip()
yaml_rel = (yaml_override if yaml_override.strip() else cfg.get("yaml_path") or "").strip()

def _local_git_commit() -> str:
    configured = (cfg.get("git_commit") or "").strip()
    if configured or bool(cfg.get("run_local")):
        return configured
    wd = (cfg.get("workdir") or "").strip()
    if not wd or not os.path.isdir(wd):
        wd = INFRA_REPO_ROOT
    try:
        r = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=wd,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception as e:
        if bool(cfg.get("strict_provenance")):
            sys.stderr.write(f"fast_submit.sh: cannot resolve git commit in {wd!r}: {e}\n")
            sys.exit(2)
        return ""
    if r.returncode != 0:
        if bool(cfg.get("strict_provenance")):
            err = (r.stderr or r.stdout or "git rev-parse failed").strip()
            sys.stderr.write(f"fast_submit.sh: cannot resolve git commit in {wd!r}: {err}\n")
            sys.exit(2)
        return ""
    return r.stdout.strip()[:12]

payload = {
    "session_key": os.environ["INFRA_SESSION_KEY"],
    "run_command": "",
    "gpu": cfg["gpu"],
    "workdir": cfg["workdir"],
    "data_version": cfg["data_version"],
    "random_seed": int(cfg["random_seed"]),
    "estimated_hours": float(cfg["estimated_hours"]),
    "use_spot": bool(cfg["use_spot"]),
    "cloud": cfg["cloud"],
    "dataset_s3": cfg["dataset_s3"],
    "output_s3": cfg["output_s3"],
    "resume_from": cfg["resume_from"],
    "config": cfg["config"] if isinstance(cfg["config"], dict) else {},
    "strict_provenance": bool(cfg["strict_provenance"]),
    "git_commit": _local_git_commit(),
    "run_local": bool(cfg["run_local"]),
    "save_log_to_workdir": bool(cfg["save_log_to_workdir"]),
    "log_dir": cfg["log_dir"],
    "local_use_bash": bool(cfg["local_use_bash"]),
    "sky_task_yaml": "",
}

if run_cmd:
    payload["run_command"] = run_cmd
elif yaml_rel:
    ypath = yaml_rel if os.path.isabs(yaml_rel) else os.path.normpath(os.path.join(INFRA_REPO_ROOT, yaml_rel))
    try:
        with open(ypath, encoding="utf-8") as yf:
            payload["sky_task_yaml"] = yf.read()
    except OSError as e:
        sys.stderr.write(f"fast_submit.sh: cannot read yaml_path {ypath!r}: {e}\n")
        sys.exit(2)
else:
    sys.stderr.write(
        "fast_submit.sh: set run_command or yaml_path in config, or pass --cmd / --yaml\n"
    )
    sys.exit(2)

print(json.dumps(payload))
PY
)"

curl -sS --max-time 300 -X POST "$URL/api/submit" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "$BODY" | pretty_json

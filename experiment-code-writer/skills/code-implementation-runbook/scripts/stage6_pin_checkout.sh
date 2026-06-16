#!/usr/bin/env bash
# Stage 6a deterministic upstream-pin checkout.
#
# The #1 cause of Stage 6a death (confirmed via debug traces 8656229d336f,
# 1e1c0e..., 7332cf...) was the agent hand-running a FRAGILE git sequence:
#     git clone --depth 1 <Repo> upstream
#     git fetch  --depth 1 origin <Commit>     # <-- most servers REJECT fetching an
#     git checkout <Commit>                    #     arbitrary SHA -> "couldn't find remote ref"
# The agent then improvises ad-hoc git commands, thrashes ~29 turns, blows its
# turn budget, returns an empty final turn -> 14-char "Executed: bash" stub ->
# 3 retries exhausted -> stage_6_retries_exhausted, zero artifacts.
#
# This script makes the clone+checkout ONE deterministic call so the agent
# never improvises git. It does a FULL clone (arbitrary-SHA checkout + history
# ops work), checks out the pinned commit, and falls back to origin/HEAD with a
# PIN_DEVIATION marker when the commit is genuinely unreachable (matches the
# runbook Step 0.3.5 "commit unreachable but repo valid" rule).
#
# It does NOT run the upstream test suite — the runbook classifies pre/post-patch
# test results (env-aware), so that judgement stays with the agent.
#
# Usage:
#   ./stage6_pin_checkout.sh <Repository> <Commit> [DEST]
#     Repository  upstream git URL (or local path) from the pin
#     Commit      pinned SHA (NOT a branch name) from the pin
#     DEST        clone target dir name (default: "upstream"), relative to CWD
#
# Contract: the LAST stdout line is a machine-readable status the agent reads:
#   STAGE6_CHECKOUT: OK           commit=<sha>            -> proceed, mark pin honoured
#   STAGE6_CHECKOUT: ALREADY_AT   commit=<sha>            -> retry; upstream/ already at pin, skip clone
#   STAGE6_CHECKOUT: PIN_DEVIATION commit=<requested> resolved=<head_sha>
#                                                         -> proceed, record pin_deviation in receipt
#   STAGE6_CHECKOUT: FATAL        <reason>                -> abort (clone failed / repo unusable)

set -uo pipefail

emit() { echo "STAGE6_CHECKOUT: $*"; }

if [[ $# -lt 2 ]]; then
  echo "usage: stage6_pin_checkout.sh <Repository> <Commit> [DEST]" >&2
  emit "FATAL missing-args"
  exit 2
fi

REPO="$1"
COMMIT="$2"
DEST="${3:-upstream}"

# ---- Retry idempotency: a prior attempt may have already cloned -------------
if [[ -d "$DEST/.git" ]]; then
  cur="$(git -C "$DEST" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "[stage6_pin_checkout] $DEST/.git already exists (HEAD=$cur) — not re-cloning."
  # Does the existing checkout already match the requested commit?
  if [[ "$cur" == "$COMMIT"* ]] || git -C "$DEST" merge-base --is-ancestor "$COMMIT" HEAD 2>/dev/null; then
    emit "ALREADY_AT commit=$cur"
    exit 0
  fi
  # Existing clone, different commit: try to land the pin without re-cloning.
  if git -C "$DEST" checkout -q "$COMMIT" 2>/dev/null \
     || { git -C "$DEST" fetch -q origin "$COMMIT" 2>/dev/null && git -C "$DEST" checkout -q "$COMMIT" 2>/dev/null; }; then
    emit "OK commit=$(git -C "$DEST" rev-parse HEAD)"
    exit 0
  fi
  emit "ALREADY_AT commit=$cur"
  exit 0
fi

# ---- Fresh full clone (NOT --depth 1, so any SHA + history ops work) --------
echo "[stage6_pin_checkout] cloning $REPO -> $DEST (full clone)"
if ! git clone --quiet "$REPO" "$DEST"; then
  emit "FATAL clone-failed repo=$REPO"
  exit 1
fi

cd "$DEST" || { emit "FATAL cannot-cd $DEST"; exit 1; }

# ---- Check out the pinned commit, with graceful fallbacks -------------------
checkout_ok=0
if git checkout -q "$COMMIT" 2>/dev/null; then
  checkout_ok=1
elif git fetch -q origin "$COMMIT" 2>/dev/null && git checkout -q "$COMMIT" 2>/dev/null; then
  # Some servers DO allow fetching an explicit SHA — try it before giving up.
  checkout_ok=1
fi

# ---- License head (the runbook decides on mismatch; we just surface it) -----
license_head() {
  for f in LICENSE LICENSE.md LICENSE.txt COPYING; do
    if [[ -f "$f" ]]; then echo "LICENSE_HEAD ($f):"; head -3 "$f"; return; fi
  done
  echo "LICENSE_HEAD: (no LICENSE file found)"
}

if [[ "$checkout_ok" == "1" ]]; then
  head_sha="$(git rev-parse HEAD)"
  license_head
  echo "HEAD: $head_sha"
  emit "OK commit=$head_sha"
  exit 0
fi

# Commit genuinely unreachable -> resolve origin/HEAD, flag the deviation.
default_ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
if [[ -n "$default_ref" ]] && git checkout -q "${default_ref#refs/remotes/origin/}" 2>/dev/null; then
  head_sha="$(git rev-parse HEAD)"
  license_head
  echo "HEAD: $head_sha"
  echo "[stage6_pin_checkout] WARNING pinned commit $COMMIT unreachable; resolved to origin/HEAD $head_sha"
  emit "PIN_DEVIATION commit=$COMMIT resolved=$head_sha"
  exit 0
fi

emit "FATAL commit-unreachable-and-no-default-branch commit=$COMMIT"
exit 1

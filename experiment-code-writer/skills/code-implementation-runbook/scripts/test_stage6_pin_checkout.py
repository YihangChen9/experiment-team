"""Hermetic tests for stage6_pin_checkout.sh.

The script replaces the fragile hand-run git sequence (`git clone --depth 1`
+ `git fetch origin <SHA>` + `git checkout <SHA>`) that most servers reject
with "couldn't find remote ref" — the documented #1 cause of Stage 6a thrash.

No network: a throwaway local git repo plays the role of the upstream remote
(`git clone <local path>` is a valid clone source).

Run with the engine repo's venv:
    .venv/bin/python -m pytest <this file> -q
"""
from __future__ import annotations

import pathlib
import subprocess

_SCRIPT = pathlib.Path(__file__).resolve().parent / "stage6_pin_checkout.sh"

_GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@t",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@t",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_SYSTEM": "/dev/null",
}


def _git(args, cwd, env_extra=None):
    import os
    env = {**os.environ, **_GIT_ENV, **(env_extra or {})}
    return subprocess.run(
        ["git", *args], cwd=str(cwd), env=env,
        capture_output=True, text=True, check=True,
    )


def _make_origin(tmp_path) -> tuple[pathlib.Path, str, str]:
    """A 2-commit origin repo. Returns (path, first_sha, head_sha)."""
    origin = tmp_path / "origin"
    origin.mkdir()
    _git(["init", "-q", "-b", "main"], origin)
    (origin / "a.txt").write_text("one\n")
    _git(["add", "."], origin)
    _git(["commit", "-q", "-m", "c1"], origin)
    first = _git(["rev-parse", "HEAD"], origin).stdout.strip()
    (origin / "b.txt").write_text("two\n")
    _git(["add", "."], origin)
    _git(["commit", "-q", "-m", "c2"], origin)
    head = _git(["rev-parse", "HEAD"], origin).stdout.strip()
    return origin, first, head


def _run(repo, commit, cwd, dest="upstream"):
    import os
    return subprocess.run(
        ["bash", str(_SCRIPT), str(repo), commit, dest],
        cwd=str(cwd), env={**os.environ, **_GIT_ENV},
        capture_output=True, text=True,
    )


def _status_line(stdout: str) -> str:
    lines = [ln for ln in stdout.splitlines() if ln.startswith("STAGE6_CHECKOUT:")]
    assert lines, f"no STAGE6_CHECKOUT status line in:\n{stdout}"
    return lines[-1]


# --- The core win: full clone + checkout of an arbitrary pinned SHA ----------

def test_checkout_pinned_commit_does_full_clone(tmp_path):
    origin, first, _head = _make_origin(tmp_path)
    work = tmp_path / "ws"; work.mkdir()
    res = _run(origin, first, work)
    assert res.returncode == 0, res.stderr + res.stdout
    assert _status_line(res.stdout) == f"STAGE6_CHECKOUT: OK commit={first}"
    # upstream/ is a FULL clone (history present), parked at the pinned commit.
    got = _git(["rev-parse", "HEAD"], work / "upstream").stdout.strip()
    assert got == first
    # full clone => the parent commit is reachable (shallow clone would 404 here)
    _git(["cat-file", "-e", f"{first}^{{commit}}"], work / "upstream")


def test_retry_does_not_reclone_and_reports_already_at(tmp_path):
    origin, first, _head = _make_origin(tmp_path)
    work = tmp_path / "ws"; work.mkdir()
    _run(origin, first, work)
    res = _run(origin, first, work)  # second invocation == a retry
    assert res.returncode == 0, res.stderr + res.stdout
    assert _status_line(res.stdout).startswith("STAGE6_CHECKOUT: ALREADY_AT")
    assert "not re-cloning" in res.stdout


def test_unreachable_commit_falls_back_to_head_with_pin_deviation(tmp_path):
    origin, _first, head = _make_origin(tmp_path)
    work = tmp_path / "ws"; work.mkdir()
    bogus = "0" * 40
    res = _run(origin, bogus, work)
    assert res.returncode == 0, res.stderr + res.stdout
    status = _status_line(res.stdout)
    assert status == f"STAGE6_CHECKOUT: PIN_DEVIATION commit={bogus} resolved={head}"
    got = _git(["rev-parse", "HEAD"], work / "upstream").stdout.strip()
    assert got == head


def test_unclonable_repo_is_fatal(tmp_path):
    work = tmp_path / "ws"; work.mkdir()
    res = _run(tmp_path / "does-not-exist", "0" * 40, work)
    assert res.returncode == 1
    assert _status_line(res.stdout).startswith("STAGE6_CHECKOUT: FATAL clone-failed")


def test_missing_args_is_fatal(tmp_path):
    import os
    res = subprocess.run(
        ["bash", str(_SCRIPT), "only-one-arg"],
        cwd=str(tmp_path), env={**os.environ, **_GIT_ENV},
        capture_output=True, text=True,
    )
    assert res.returncode == 2
    assert _status_line(res.stdout).startswith("STAGE6_CHECKOUT: FATAL missing-args")

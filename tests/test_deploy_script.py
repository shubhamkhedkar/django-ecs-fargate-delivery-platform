"""The deploy script must be safe by default: dry-run, no AWS calls, strict inputs."""

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "deploy.sh"


@pytest.fixture
def trap_path(tmp_path):
    """A PATH where aws/docker/terraform exist but record any call and fail."""
    calls = tmp_path / "calls.log"
    for tool in ("aws", "docker", "terraform", "jq"):
        shim = tmp_path / tool
        shim.write_text(f'#!/bin/sh\necho "{tool} $*" >> "{calls}"\nexit 97\n')
        shim.chmod(0o755)
    env = {**os.environ, "PATH": f"{tmp_path}:{os.environ['PATH']}"}
    env.pop("EXPECTED_ACCOUNT_ID", None)
    return env, calls


def run(args, env):
    return subprocess.run(
        ["bash", str(SCRIPT), *args], env=env, capture_output=True, text=True, cwd=ROOT
    )


def test_dry_run_prints_plan_and_calls_nothing(trap_path):
    env, calls = trap_path
    result = run(["--tag", "abc1234"], env)
    assert result.returncode == 0, result.stderr
    out = result.stdout
    for step in ("1/6 build", "2/6 push", "3/6 wait for ECR scan", "5/6 run database", "6/6"):
        assert step in out
    assert "[dry-run] docker push" in out
    assert "aws ecs update-service" in out
    assert not calls.exists(), calls.read_text()


def test_apply_requires_expected_account(trap_path):
    env, calls = trap_path
    result = run(["--apply", "--tag", "abc1234"], env)
    assert result.returncode != 0
    assert "EXPECTED_ACCOUNT_ID" in result.stderr
    assert not calls.exists()


def test_apply_refuses_wrong_account(tmp_path, trap_path):
    env, _ = trap_path
    (tmp_path / "aws").write_text("#!/bin/sh\necho 999999999999\n")
    result = run(["--apply", "--tag", "abc1234"], {**env, "EXPECTED_ACCOUNT_ID": "111122223333"})
    assert result.returncode != 0
    assert "expected 111122223333" in result.stderr


@pytest.mark.parametrize("tag", ["latest", "v1.0", "ABC1234", "abc"])
def test_rejects_mutable_or_bad_tags(trap_path, tag):
    env, _ = trap_path
    result = run(["--tag", tag], env)
    assert result.returncode != 0
    assert "must be a git SHA" in result.stderr


def test_rejects_unknown_platform(trap_path):
    env, _ = trap_path
    result = run(["--tag", "abc1234", "--platform", "windows/amd64"], env)
    assert result.returncode != 0


def test_help(trap_path):
    env, _ = trap_path
    result = run(["--help"], env)
    assert result.returncode == 0
    assert "--apply" in result.stdout

"""Static guardrails for the Dockerfile and compose stack."""

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DOCKERFILE = (ROOT / "Dockerfile").read_text()


def test_multi_stage_build():
    assert DOCKERFILE.count("\nFROM ") + DOCKERFILE.startswith("FROM ") >= 2
    assert "COPY --from=builder /opt/venv /opt/venv" in DOCKERFILE


def test_runs_as_non_root_numeric_user():
    user_lines = [line for line in DOCKERFILE.splitlines() if line.startswith("USER ")]
    assert user_lines == ["USER 10001:10001"]


def test_has_healthcheck_and_gunicorn():
    assert "HEALTHCHECK" in DOCKERFILE
    assert '"gunicorn"' in DOCKERFILE


def test_no_secrets_baked_into_image():
    for forbidden in ("DJANGO_SECRET_KEY=", "DB_PASSWORD=", "AWS_SECRET_ACCESS_KEY"):
        assert forbidden not in DOCKERFILE


def test_dockerignore_is_allowlist():
    lines = (ROOT / ".dockerignore").read_text().splitlines()
    assert lines[0] == "*"
    assert "!app/" in lines


def test_compose_app_containers_are_hardened():
    compose = yaml.safe_load((ROOT / "compose.yaml").read_text())
    for name in ("web", "migrate"):
        svc = compose["services"][name]
        assert svc["read_only"] is True
        assert svc["cap_drop"] == ["ALL"]
        assert "no-new-privileges:true" in svc["security_opt"]


def test_compose_publishes_web_on_loopback_only():
    compose = yaml.safe_load((ROOT / "compose.yaml").read_text())
    ports = compose["services"]["web"]["ports"]
    assert all(p.startswith("127.0.0.1:") for p in ports)
    assert "ports" not in compose["services"]["db"]


def test_gunicorn_keepalive_exceeds_alb_idle_timeout():
    namespace: dict = {}
    exec((ROOT / "app" / "gunicorn.conf.py").read_text(), namespace)  # noqa: S102
    assert namespace["keepalive"] > 60
    assert namespace["graceful_timeout"] < 30

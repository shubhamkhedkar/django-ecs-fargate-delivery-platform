"""Settings are evaluated in a fresh interpreter so env changes don't leak between tests."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

APP_DIR = Path(__file__).resolve().parents[1] / "app"

PROBE = """
import json, django
from django.conf import settings
django.setup()
db = settings.DATABASES["default"]
print(json.dumps({
    "debug": settings.DEBUG,
    "engine": db["ENGINE"],
    "host": db.get("HOST", ""),
    "sslmode": db.get("OPTIONS", {}).get("sslmode"),
    "hosts": settings.ALLOWED_HOSTS,
    "ssl_redirect": settings.SECURE_SSL_REDIRECT,
    "hsts": settings.SECURE_HSTS_SECONDS,
    "secure_cookies": settings.SESSION_COOKIE_SECURE,
    "first_middleware": settings.MIDDLEWARE[0],
}))
"""

CLEAN_KEYS = (
    "DJANGO_DEBUG",
    "DJANGO_SECRET_KEY",
    "DJANGO_ALLOW_INSECURE_KEY",
    "DJANGO_ALLOWED_HOSTS",
    "DJANGO_SECURE_SSL_REDIRECT",
    "DJANGO_SECURE_COOKIES",
    "DJANGO_HSTS_SECONDS",
    "DB_HOST",
    "DB_SSLMODE",
)


def run_settings(**env):
    base = {k: v for k, v in os.environ.items() if k not in CLEAN_KEYS}
    base.update({"DJANGO_SETTINGS_MODULE": "config.settings", **env})
    return subprocess.run(
        [sys.executable, "-c", PROBE], cwd=APP_DIR, env=base, capture_output=True, text=True
    )


def probe(**env):
    result = run_settings(**env)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_production_requires_secret_key():
    result = run_settings()
    assert result.returncode != 0
    assert "DJANGO_SECRET_KEY is required" in result.stderr


def test_production_defaults_are_hardened():
    cfg = probe(DJANGO_SECRET_KEY="x" * 50, DJANGO_ALLOWED_HOSTS="ledger.example.com")
    assert cfg["debug"] is False
    assert cfg["ssl_redirect"] is True
    assert cfg["secure_cookies"] is True
    assert cfg["hsts"] == 31536000
    assert cfg["hosts"] == ["ledger.example.com"]
    assert cfg["first_middleware"] == "config.health.HealthCheckMiddleware"


def test_postgres_selected_when_db_host_set():
    cfg = probe(DJANGO_SECRET_KEY="x" * 50, DB_HOST="db.internal")
    assert cfg["engine"] == "django.db.backends.postgresql"
    assert cfg["host"] == "db.internal"
    assert cfg["sslmode"] == "require"


def test_sqlite_fallback_without_db_host():
    cfg = probe(DJANGO_DEBUG="true")
    assert cfg["engine"] == "django.db.backends.sqlite3"
    assert cfg["ssl_redirect"] is False


def test_invalid_boolean_is_rejected():
    result = run_settings(DJANGO_DEBUG="maybe")
    assert result.returncode != 0
    assert "must be a boolean" in result.stderr


@pytest.mark.parametrize("flag", ["1", "true", "YES", "on"])
def test_truthy_values(flag):
    assert probe(DJANGO_DEBUG=flag)["debug"] is True


def test_deploy_check_passes_with_production_env():
    env = {k: v for k, v in os.environ.items() if k not in CLEAN_KEYS}
    env.update(
        DJANGO_SETTINGS_MODULE="config.settings",
        DJANGO_SECRET_KEY="k" * 64 + "-production-like-random-value-for-check",
        DJANGO_ALLOWED_HOSTS="ledger.example.com",
    )
    result = subprocess.run(
        [sys.executable, "manage.py", "check", "--deploy", "--fail-level", "ERROR"],
        cwd=APP_DIR,
        env=env,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    # HSTS preload is deliberately opt-in (DJANGO_HSTS_PRELOAD); nothing else may warn.
    warnings = [line for line in output.splitlines() if "?: (security." in line]
    assert all("security.W021" in line for line in warnings), output

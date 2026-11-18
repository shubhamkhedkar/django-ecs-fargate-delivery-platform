import pytest
from django.core.exceptions import ValidationError
from django.core.management import call_command
from ledger.models import Release


@pytest.fixture
def releases(db):
    Release.objects.create(service="api", version="1.0.0", environment="prod", status="succeeded")
    Release.objects.create(service="api", version="1.1.0", environment="prod", status="succeeded")
    Release.objects.create(service="api", version="1.2.0", environment="prod", status="failed")
    Release.objects.create(
        service="web", version="3.0.0", environment="staging", status="succeeded"
    )
    return Release.objects.all()


def test_index_renders(client, releases):
    response = client.get("/")
    assert response.status_code == 200
    body = response.content.decode()
    assert "Release Ledger" in body
    assert "1.2.0" in body


def test_list_api_returns_newest_first(client, releases):
    data = client.get("/api/releases/").json()
    assert data["count"] == 4
    assert data["results"][0]["service"] == "web"


def test_list_api_filters(client, releases):
    data = client.get("/api/releases/?environment=prod&service=api").json()
    assert data["count"] == 3
    assert {r["environment"] for r in data["results"]} == {"prod"}


def test_list_api_rejects_unknown_environment(client, releases):
    response = client.get("/api/releases/?environment=qa")
    assert response.status_code == 400


@pytest.mark.parametrize(("raw", "expected"), [("2", 2), ("0", 1), ("9999", 4), ("abc", 4)])
def test_list_api_limit_is_clamped(client, releases, raw, expected):
    assert client.get(f"/api/releases/?limit={raw}").json()["count"] == expected


def test_summary_uses_latest_successful_release(client, releases):
    envs = client.get("/api/releases/current/").json()["environments"]
    assert [r["version"] for r in envs["prod"]] == ["1.1.0"]
    assert [r["version"] for r in envs["staging"]] == ["3.0.0"]
    assert envs["dev"] == []


def test_api_is_read_only(client, releases):
    assert client.post("/api/releases/", {"service": "x"}).status_code == 405


def test_version_endpoint(client, settings):
    settings.APP_VERSION = "1.4.2"
    settings.GIT_SHA = "abc123"
    settings.DEPLOY_ENVIRONMENT = "prod"
    assert client.get("/version").json() == {
        "version": "1.4.2",
        "git_sha": "abc123",
        "environment": "prod",
    }


def test_service_name_validation(db):
    release = Release(service="Bad_Name", version="1", environment="dev")
    with pytest.raises(ValidationError):
        release.full_clean()


def test_str(db):
    r = Release(service="api", version="2.0.0", environment="prod", status="succeeded")
    assert str(r) == "api@2.0.0 -> prod (succeeded)"


def test_seed_demo_is_idempotent(db):
    call_command("seed_demo")
    first = Release.objects.count()
    call_command("seed_demo")
    assert Release.objects.count() == first > 0


def test_admin_requires_login(client, db):
    response = client.get("/admin/")
    assert response.status_code == 302
    assert "/admin/login/" in response["Location"]


def test_security_headers(client, db):
    response = client.get("/")
    assert response["X-Frame-Options"] == "DENY"
    assert response["X-Content-Type-Options"] == "nosniff"
    assert response["Referrer-Policy"] == "same-origin"


def test_no_pending_migrations(db):
    call_command("makemigrations", "--check", "--dry-run", verbosity=0)

from unittest import mock

import pytest
from django.db import DatabaseError


def test_liveness_ok(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert response["Cache-Control"] == "no-store"


def test_liveness_ignores_unknown_host(client):
    # ALB health checks use the task IP as Host; that must not trip ALLOWED_HOSTS.
    response = client.get("/healthz", HTTP_HOST="10.0.12.34:8000")
    assert response.status_code == 200


def test_liveness_not_redirected_when_ssl_redirect_on(client, settings):
    settings.SECURE_SSL_REDIRECT = True
    assert client.get("/healthz").status_code == 200
    assert client.get("/version").status_code == 301


def test_other_paths_still_validate_host(client):
    assert client.get("/version", HTTP_HOST="evil.example.com").status_code == 400


@pytest.mark.django_db
def test_readiness_ok(client):
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json()["checks"]["database"] == "ok"


@pytest.mark.django_db
def test_readiness_reports_database_failure(client):
    with mock.patch("config.health.connections") as conns:
        conns.__iter__.return_value = iter(["default"])
        conns.__getitem__.return_value.cursor.side_effect = DatabaseError("down")
        response = client.get("/readyz")
    assert response.status_code == 503
    assert response.json() == {"status": "unavailable", "checks": {"database": "error"}}


def test_health_post_falls_through(client):
    # Only GET/HEAD are probes; anything else goes through the normal stack (404 here).
    assert client.post("/healthz").status_code == 404


def test_head_liveness(client):
    assert client.head("/healthz").status_code == 200

"""Liveness and readiness probes.

ALB target-group health checks send the task's private IP as the Host header, which
would fail ALLOWED_HOSTS validation, and they speak plain HTTP, which SECURE_SSL_REDIRECT
would bounce. Answering the probes here, ahead of SecurityMiddleware/CommonMiddleware,
keeps both protections switched on for real traffic.
"""

from __future__ import annotations

import logging

from django.db import DatabaseError, connections
from django.http import HttpRequest, HttpResponse, JsonResponse

logger = logging.getLogger(__name__)

LIVENESS_PATH = "/healthz"
READINESS_PATH = "/readyz"


def database_ready() -> bool:
    try:
        for alias in connections:
            with connections[alias].cursor() as cursor:
                cursor.execute("SELECT 1")
    except DatabaseError:
        logger.warning("readiness check: database unavailable", exc_info=True)
        return False
    return True


class HealthCheckMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        if request.method in {"GET", "HEAD"}:
            if request.path == LIVENESS_PATH:
                return self._no_store(JsonResponse({"status": "ok"}))
            if request.path == READINESS_PATH:
                if database_ready():
                    body = {"status": "ready", "checks": {"database": "ok"}}
                    return self._no_store(JsonResponse(body))
                body = {"status": "unavailable", "checks": {"database": "error"}}
                return self._no_store(JsonResponse(body, status=503))
        return self.get_response(request)

    @staticmethod
    def _no_store(response: HttpResponse) -> HttpResponse:
        response["Cache-Control"] = "no-store"
        return response

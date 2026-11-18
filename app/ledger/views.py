from django.conf import settings
from django.http import HttpRequest, JsonResponse
from django.shortcuts import render
from django.views.decorators.http import require_GET

from ledger.models import Release

MAX_LIMIT = 200


def _limit(request: HttpRequest, default: int = 50) -> int:
    try:
        value = int(request.GET.get("limit", default))
    except ValueError:
        return default
    return max(1, min(value, MAX_LIMIT))


@require_GET
def index(request: HttpRequest):
    releases = Release.objects.all()[:20]
    return render(
        request,
        "ledger/index.html",
        {"releases": releases, "current": current_by_environment(), "build": build_info()},
    )


@require_GET
def release_list(request: HttpRequest) -> JsonResponse:
    qs = Release.objects.all()
    environment = request.GET.get("environment")
    if environment:
        if environment not in Release.Environment.values:
            return JsonResponse({"error": f"unknown environment {environment!r}"}, status=400)
        qs = qs.filter(environment=environment)
    service = request.GET.get("service")
    if service:
        qs = qs.filter(service=service)
    items = [r.as_dict() for r in qs[: _limit(request)]]
    return JsonResponse({"count": len(items), "results": items})


def current_by_environment() -> dict[str, list[dict]]:
    """Latest successful release of every service, grouped by environment."""
    summary: dict[str, list[dict]] = {env: [] for env in Release.Environment.values}
    seen: set[tuple[str, str]] = set()
    for release in Release.objects.filter(status=Release.Status.SUCCEEDED):
        key = (release.environment, release.service)
        if key in seen:
            continue
        seen.add(key)
        summary[release.environment].append(release.as_dict())
    return summary


@require_GET
def release_summary(request: HttpRequest) -> JsonResponse:
    return JsonResponse({"environments": current_by_environment()})


def build_info() -> dict[str, str]:
    return {
        "version": settings.APP_VERSION,
        "git_sha": settings.GIT_SHA,
        "environment": settings.DEPLOY_ENVIRONMENT,
    }


@require_GET
def version(request: HttpRequest) -> JsonResponse:
    return JsonResponse(build_info())

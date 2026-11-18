"""Test settings: production-style config (DEBUG off) over plain HTTP and SQLite."""

import os

os.environ.setdefault("DJANGO_SECRET_KEY", "test-only-key-not-used-anywhere-else")
os.environ.setdefault("DJANGO_ALLOWED_HOSTS", "testserver,localhost")
os.environ.setdefault("DJANGO_SECURE_SSL_REDIRECT", "false")
os.environ.setdefault("DJANGO_SECURE_COOKIES", "false")
os.environ.setdefault("DJANGO_HSTS_SECONDS", "0")
os.environ.pop("DB_HOST", None)

from config.settings import *  # noqa: F403

# collectstatic is not run for unit tests; the image build covers the manifest storage.
STORAGES = {
    **STORAGES,  # noqa: F405
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}
WHITENOISE_AUTOREFRESH = True

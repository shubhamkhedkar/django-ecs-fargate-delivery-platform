"""Settings for the release ledger.

Everything that differs between a laptop, docker compose and ECS Fargate comes from
environment variables. On ECS, secrets (DJANGO_SECRET_KEY, DB_USER, DB_PASSWORD) are
injected by the task definition from AWS Secrets Manager; they never live in the image.
"""

from __future__ import annotations

from pathlib import Path

from django.core.exceptions import ImproperlyConfigured

from config.env import env_bool, env_int, env_list, env_str

BASE_DIR = Path(__file__).resolve().parent.parent

DEBUG = env_bool("DJANGO_DEBUG", False)

SECRET_KEY = env_str("DJANGO_SECRET_KEY")
if not SECRET_KEY:
    # Only local runs, tests and the image build step (collectstatic) may fall back.
    if DEBUG or env_bool("DJANGO_ALLOW_INSECURE_KEY", False):
        SECRET_KEY = "insecure-placeholder-for-local-runs-only"  # noqa: S105
    else:
        raise ImproperlyConfigured("DJANGO_SECRET_KEY is required when DJANGO_DEBUG is false")

ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")
CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")

APP_VERSION = env_str("APP_VERSION", "0.0.0-dev")
GIT_SHA = env_str("GIT_SHA", "unknown")
DEPLOY_ENVIRONMENT = env_str("DEPLOY_ENVIRONMENT", "local")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "whitenoise.runserver_nostatic",
    "django.contrib.staticfiles",
    "ledger",
]

MIDDLEWARE = [
    # Must stay first: answers ALB/ECS probes before host validation and SSL redirects.
    "config.health.HealthCheckMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

# --- Database -----------------------------------------------------------------
# DB_HOST set -> PostgreSQL (RDS on AWS, the "db" service in compose).
# DB_HOST unset -> SQLite, for tests and quick local runs only.
if env_str("DB_HOST"):
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "HOST": env_str("DB_HOST"),
            "PORT": env_int("DB_PORT", 5432),
            "NAME": env_str("DB_NAME", "ledger"),
            "USER": env_str("DB_USER", "ledger"),
            "PASSWORD": env_str("DB_PASSWORD"),
            "CONN_MAX_AGE": env_int("DB_CONN_MAX_AGE", 60),
            "CONN_HEALTH_CHECKS": True,
            "OPTIONS": {
                "sslmode": env_str("DB_SSLMODE", "require"),
                "connect_timeout": env_int("DB_CONNECT_TIMEOUT", 5),
                "application_name": "release-ledger",
            },
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": env_str("SQLITE_PATH", str(BASE_DIR / "db.sqlite3")),
        }
    }

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 12},
    },
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

# --- Static files (served by WhiteNoise from the image) ---------------------------
STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}

ADMIN_URL = env_str("DJANGO_ADMIN_URL", "admin/")

# --- Security -------------------------------------------------------------------
# TLS terminates at the ALB, which sets X-Forwarded-Proto.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", not DEBUG)
SESSION_COOKIE_SECURE = env_bool("DJANGO_SECURE_COOKIES", not DEBUG)
CSRF_COOKIE_SECURE = SESSION_COOKIE_SECURE
SESSION_COOKIE_HTTPONLY = True
SECURE_HSTS_SECONDS = env_int("DJANGO_HSTS_SECONDS", 0 if DEBUG else 31536000)
SECURE_HSTS_INCLUDE_SUBDOMAINS = SECURE_HSTS_SECONDS > 0
SECURE_HSTS_PRELOAD = env_bool("DJANGO_HSTS_PRELOAD", False)
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
SECURE_CROSS_ORIGIN_OPENER_POLICY = "same-origin"
X_FRAME_OPTIONS = "DENY"

# --- Logging: one JSON object per line on stdout -> CloudWatch Logs ---------------
LOG_LEVEL = env_str("DJANGO_LOG_LEVEL", "INFO").upper()
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"json": {"()": "config.logging.JsonFormatter"}},
    "handlers": {"stdout": {"class": "logging.StreamHandler", "formatter": "json"}},
    "root": {"handlers": ["stdout"], "level": LOG_LEVEL},
    "loggers": {
        "django.request": {"handlers": ["stdout"], "level": "WARNING", "propagate": False},
        "django.security": {"handlers": ["stdout"], "level": "WARNING", "propagate": False},
    },
}

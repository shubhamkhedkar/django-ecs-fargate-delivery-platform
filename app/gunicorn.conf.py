"""Gunicorn settings tuned for Fargate behind an Application Load Balancer."""

import multiprocessing
import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8000')}"
worker_class = "gthread"
workers = int(os.environ.get("WEB_CONCURRENCY", min(multiprocessing.cpu_count() * 2 + 1, 4)))
threads = int(os.environ.get("GUNICORN_THREADS", "4"))
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "30"))
graceful_timeout = 25  # below the ECS stopTimeout (30s) so in-flight requests finish
# Longer than the ALB idle timeout (60s) so the ALB, not gunicorn, closes idle
# connections; the other way round produces intermittent 502s.
keepalive = 75
max_requests = 2000
max_requests_jitter = 200
worker_tmp_dir = os.environ.get("GUNICORN_WORKER_TMP_DIR", "/tmp")  # noqa: S108
forwarded_allow_ips = os.environ.get("FORWARDED_ALLOW_IPS", "*")
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("GUNICORN_LOG_LEVEL", "info")
access_log_format = (
    '{"remote":"%(h)s","method":"%(m)s","path":"%(U)s","status":%(s)s,'
    '"bytes":"%(B)s","duration_us":%(D)s,"agent":"%(a)s"}'
)

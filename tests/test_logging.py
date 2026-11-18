import json
import logging

from config.logging import JsonFormatter


def test_json_formatter_emits_one_object():
    record = logging.LogRecord("app", logging.WARNING, __file__, 1, "hello %s", ("world",), None)
    record.status_code = 503
    payload = json.loads(JsonFormatter().format(record))
    assert payload["message"] == "hello world"
    assert payload["level"] == "WARNING"
    assert payload["status_code"] == 503
    assert payload["ts"].endswith("+00:00")


def test_json_formatter_includes_exception():
    try:
        raise ValueError("boom")
    except ValueError:
        import sys

        record = logging.LogRecord("app", logging.ERROR, __file__, 1, "failed", (), sys.exc_info())
    payload = json.loads(JsonFormatter().format(record))
    assert "ValueError: boom" in payload["exc_info"]

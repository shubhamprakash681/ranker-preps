"""Structured JSON logging, one object per line on stdout (CloudWatch and Cloud Logging both parse it)."""
import contextvars
import json
import logging
import sys
import time

from .config import get_settings

trace_id_var: contextvars.ContextVar[str] = contextvars.ContextVar("trace_id", default="")


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        s = get_settings()
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)) + f".{int(record.msecs):03d}Z",
            "severity": record.levelname,  # Cloud Logging reads `severity`
            "message": record.getMessage(),
            "service": s.service_name,
            "cloud": s.cloud,
            "trace_id": trace_id_var.get(),
        }
        extra = getattr(record, "fields", None)
        if extra:
            entry.update(extra)
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def configure_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(get_settings().log_level)
    logging.getLogger("uvicorn.access").disabled = True  # we log requests ourselves


def log(logger: logging.Logger, level: int, msg: str, **fields) -> None:
    logger.log(level, msg, extra={"fields": fields})

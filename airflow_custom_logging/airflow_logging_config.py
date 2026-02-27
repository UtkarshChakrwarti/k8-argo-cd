"""Minimal Airflow logging config with Kubernetes task-log fallback.

This module intentionally avoids importing ``airflow`` at import time to
prevent recursive logging-config initialization in Airflow 3.
"""

from __future__ import annotations


LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "airflow": {
            "format": "[%(asctime)s] {%(filename)s:%(lineno)d} %(levelname)s - %(message)s",
        },
    },
    "handlers": {
        "console": {
            "class": "airflow.utils.log.logging_mixin.RedirectStdHandler",
            "formatter": "airflow",
            "stream": "sys.stdout",
        },
        "task": {
            "class": "airflow_logging_k8s_handler.KubernetesPodFallbackTaskHandler",
            "formatter": "airflow",
            "base_log_folder": "/home/airflow/logs",
        },
    },
    "loggers": {
        "airflow.task": {
            "handlers": ["task"],
            "level": "INFO",
            "propagate": True,
        },
        "flask_appbuilder": {
            "handlers": ["console"],
            "level": "WARN",
            "propagate": True,
        },
    },
    "root": {
        "handlers": ["console"],
        "level": "INFO",
    },
}

# Airflow loads this symbol from the same module.
REMOTE_TASK_LOG = None

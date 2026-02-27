"""Airflow logging config that swaps task handler to Kubernetes fallback."""

from __future__ import annotations

import os
from typing import Any

from airflow.configuration import conf

LOG_LEVEL: str = conf.get_mandatory_value("logging", "LOGGING_LEVEL").upper()
FAB_LOG_LEVEL: str = conf.get_mandatory_value("logging", "FAB_LOGGING_LEVEL").upper()
LOG_FORMAT: str = conf.get_mandatory_value("logging", "LOG_FORMAT")
DAG_PROCESSOR_LOG_FORMAT: str = conf.get_mandatory_value("logging", "DAG_PROCESSOR_LOG_FORMAT")
LOG_FORMATTER_CLASS: str = conf.get_mandatory_value(
    "logging",
    "LOG_FORMATTER_CLASS",
    fallback="airflow.utils.log.timezone_aware.TimezoneAware",
)
COLORED_LOG_FORMAT: str = conf.get_mandatory_value("logging", "COLORED_LOG_FORMAT")
COLORED_LOG: bool = conf.getboolean("logging", "COLORED_CONSOLE_LOG")
COLORED_FORMATTER_CLASS: str = conf.get_mandatory_value("logging", "COLORED_FORMATTER_CLASS")
BASE_LOG_FOLDER: str = os.path.expanduser(conf.get_mandatory_value("logging", "BASE_LOG_FOLDER"))

LOGGING_CONFIG: dict[str, Any] = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "airflow": {
            "format": LOG_FORMAT,
            "class": LOG_FORMATTER_CLASS,
        },
        "airflow_coloured": {
            "format": COLORED_LOG_FORMAT if COLORED_LOG else LOG_FORMAT,
            "class": COLORED_FORMATTER_CLASS if COLORED_LOG else LOG_FORMATTER_CLASS,
        },
        "source_processor": {
            "format": DAG_PROCESSOR_LOG_FORMAT,
            "class": LOG_FORMATTER_CLASS,
        },
    },
    "filters": {
        "mask_secrets": {
            "()": "airflow.sdk.execution_time.secrets_masker.SecretsMasker",
        },
    },
    "handlers": {
        "console": {
            "class": "airflow.utils.log.logging_mixin.RedirectStdHandler",
            "formatter": "airflow_coloured",
            "stream": "sys.stdout",
            "filters": ["mask_secrets"],
        },
        "task": {
            "class": "airflow_logging_k8s_handler.KubernetesPodFallbackTaskHandler",
            "formatter": "airflow",
            "base_log_folder": BASE_LOG_FOLDER,
            "filters": ["mask_secrets"],
        },
    },
    "loggers": {
        "airflow.task": {
            "handlers": ["task"],
            "level": LOG_LEVEL,
            "propagate": True,
            "filters": ["mask_secrets"],
        },
        "flask_appbuilder": {
            "handlers": ["console"],
            "level": FAB_LOG_LEVEL,
            "propagate": True,
        },
    },
    "root": {
        "handlers": ["console"],
        "level": LOG_LEVEL,
        "filters": ["mask_secrets"],
    },
}

EXTRA_LOGGER_NAMES: str | None = conf.get("logging", "EXTRA_LOGGER_NAMES", fallback=None)
if EXTRA_LOGGER_NAMES:
    new_loggers = {
        logger_name.strip(): {
            "handlers": ["console"],
            "level": LOG_LEVEL,
            "propagate": True,
        }
        for logger_name in EXTRA_LOGGER_NAMES.split(",")
    }
    LOGGING_CONFIG["loggers"].update(new_loggers)

REMOTE_TASK_LOG = None

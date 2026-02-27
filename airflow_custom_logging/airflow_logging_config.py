"""Airflow logging config: default + Kubernetes pod-log fallback for task logs."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from airflow.config_templates.airflow_local_settings import DEFAULT_LOGGING_CONFIG

# Start from Airflow's supported default logging dictionary to avoid config-import
# recursion during startup. Then only replace the task handler.
LOGGING_CONFIG: dict[str, Any] = deepcopy(DEFAULT_LOGGING_CONFIG)
LOGGING_CONFIG["handlers"]["task"]["class"] = (
    "airflow_logging_k8s_handler.KubernetesPodFallbackTaskHandler"
)

# Airflow imports this symbol from custom logging modules in some code paths.
# Keep it nullable so FileTaskHandler does not treat it as a remote logger object.
REMOTE_TASK_LOG = None

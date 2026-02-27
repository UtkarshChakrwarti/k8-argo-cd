"""Kubernetes pod-log fallback for Airflow task log reads."""

from __future__ import annotations

import os
from typing import Any

from airflow.utils.log.file_task_handler import FileTaskHandler
from kubernetes import client as k8s_client
from kubernetes import config as k8s_config
from kubernetes.config.config_exception import ConfigException


class KubernetesPodFallbackTaskHandler(FileTaskHandler):
    """Use Kubernetes API pod logs when served logs are unavailable."""

    _core_v1: k8s_client.CoreV1Api | None = None

    @classmethod
    def _get_core_v1(cls) -> k8s_client.CoreV1Api:
        if cls._core_v1 is None:
            try:
                k8s_config.load_incluster_config()
            except ConfigException:
                k8s_config.load_kube_config()
            cls._core_v1 = k8s_client.CoreV1Api()
        return cls._core_v1

    @staticmethod
    def _namespace_from_executor_config(ti: Any) -> str | None:
        executor_config = getattr(ti, "executor_config", {}) or {}
        pod_override = executor_config.get("pod_override")
        if isinstance(pod_override, dict):
            metadata = pod_override.get("metadata") or {}
            return metadata.get("namespace")
        metadata = getattr(pod_override, "metadata", None)
        return getattr(metadata, "namespace", None)

    @classmethod
    def _candidate_namespaces(cls, ti: Any) -> list[str]:
        namespaces: list[str] = []
        explicit_ns = cls._namespace_from_executor_config(ti)
        if explicit_ns:
            namespaces.append(explicit_ns)
        default_ns = os.getenv("AIRFLOW__KUBERNETES_EXECUTOR__NAMESPACE", "airflow-user")
        if default_ns:
            namespaces.append(default_ns)
        multi_ns = os.getenv(
            "AIRFLOW__KUBERNETES_EXECUTOR__MULTI_NAMESPACE_MODE_NAMESPACE_LIST",
            "",
        )
        namespaces.extend(ns.strip() for ns in multi_ns.split(",") if ns.strip())
        return list(dict.fromkeys(namespaces))

    def _read_from_kubernetes_api(self, ti: Any) -> tuple[list[str], list[str]]:
        pod_name = getattr(ti, "hostname", None)
        if not pod_name:
            return [], []

        try:
            api = self._get_core_v1()
        except Exception as exc:  # noqa: BLE001
            return [f"Could not initialize Kubernetes API client: {exc}"], []
        namespaces = self._candidate_namespaces(ti)
        last_error: Exception | None = None

        for namespace in namespaces:
            for container in ("base", None):
                try:
                    log_text = api.read_namespaced_pod_log(
                        name=pod_name,
                        namespace=namespace,
                        container=container,
                        timestamps=True,
                        _preload_content=True,
                    )
                    if log_text:
                        source = f"kubernetes://{namespace}/{pod_name}"
                        if container:
                            source = f"{source}?container={container}"
                        return [source], [log_text]
                except Exception as exc:  # noqa: BLE001
                    last_error = exc

        detail = f"Could not read Kubernetes pod logs for pod={pod_name} namespaces={namespaces}"
        if last_error:
            detail = f"{detail}: {last_error}"
        return [detail], []

    def _read_from_logs_server(self, ti: Any, worker_log_rel_path: str) -> tuple[list[str], list[str]]:
        sources, logs = super()._read_from_logs_server(ti, worker_log_rel_path)
        if logs:
            return sources, logs

        # Served logs can fail for KubernetesExecutor pods; use pod logs as fallback.
        k8s_sources, k8s_logs = self._read_from_kubernetes_api(ti)
        if k8s_logs:
            return k8s_sources, k8s_logs
        return sources + k8s_sources, logs + k8s_logs

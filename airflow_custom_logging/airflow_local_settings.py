"""Airflow local settings hooks for namespace-driven task pod placement."""

from __future__ import annotations

from kubernetes.client import models as k8s

__all__ = ["pod_mutation_hook"]


def _dedicated_toleration(pool: str) -> list[k8s.V1Toleration]:
    return [
        k8s.V1Toleration(
            key="dedicated",
            operator="Equal",
            value=pool,
            effect="NoSchedule",
        )
    ]


def pod_mutation_hook(pod: k8s.V1Pod) -> None:
    """Namespace decides nodeSelector+toleration for KubernetesExecutor pods."""
    if pod is None or pod.metadata is None or pod.spec is None:
        return

    namespace = (pod.metadata.namespace or "").strip()
    if namespace == "airflow-core":
        pod.spec.node_selector = {"workload": "airflow-core"}
        pod.spec.tolerations = _dedicated_toleration("airflow-core")
    elif namespace == "airflow-user":
        pod.spec.node_selector = {"workload": "airflow-user"}
        pod.spec.tolerations = _dedicated_toleration("airflow-user")

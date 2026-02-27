"""Namespace-first executor config helpers for KubernetesExecutor DAGs."""

from __future__ import annotations

from kubernetes.client import models as k8s


def namespace_executor_config(namespace: str) -> dict:
    """Return executor_config that routes a task pod to the given namespace."""
    if not namespace or not namespace.strip():
        raise ValueError("namespace must be a non-empty string")
    normalized = namespace.strip()

    node_selector = None
    tolerations = None
    if normalized == "airflow-core":
        node_selector = {"workload": "airflow-core"}
        tolerations = [
            k8s.V1Toleration(
                key="dedicated",
                operator="Equal",
                value="airflow-core",
                effect="NoSchedule",
            )
        ]
    elif normalized == "airflow-user":
        node_selector = {"workload": "airflow-user"}
        tolerations = [
            k8s.V1Toleration(
                key="dedicated",
                operator="Equal",
                value="airflow-user",
                effect="NoSchedule",
            )
        ]

    return {
        "pod_override": k8s.V1Pod(
            metadata=k8s.V1ObjectMeta(namespace=normalized),
            spec=k8s.V1PodSpec(
                node_selector=node_selector,
                tolerations=tolerations,
            ),
        )
    }

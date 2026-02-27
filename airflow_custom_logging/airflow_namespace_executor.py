"""Namespace-first executor config helpers for KubernetesExecutor DAGs."""

from __future__ import annotations

from kubernetes.client import models as k8s


def namespace_executor_config(namespace: str) -> dict:
    """Return executor_config that routes a task pod to the given namespace."""
    if not namespace or not namespace.strip():
        raise ValueError("namespace must be a non-empty string")
    return {
        "pod_override": k8s.V1Pod(
            metadata=k8s.V1ObjectMeta(namespace=namespace.strip()),
        )
    }

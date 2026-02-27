"""
Example DAG: One run using both airflow-user and airflow-core task routing.

- default task: airflow-user namespace + user node pool
- core task: airflow-core namespace + core node pool (via pod_template_file)
"""

from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator
from kubernetes.client import models as k8s

CORE_EXECUTOR_CONFIG = {
    "pod_template_file": "/home/airflow/pod_templates/pod_template_core.yaml",
    "pod_override": k8s.V1Pod(
        metadata=k8s.V1ObjectMeta(namespace="airflow-core"),
    ),
}

with DAG(
    dag_id="example_mixed_namespace",
    start_date=datetime(2024, 1, 1),
    schedule="4-59/5 * * * *",
    catchup=False,
    tags=["namespace-demo", "mixed"],
):
    default_user_task = BashOperator(
        task_id="default_user_task",
        bash_command=(
            "NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace) && "
            "echo \"Task=default_user_task Namespace=$NAMESPACE Host=$(hostname)\""
        ),
    )

    core_routed_task = BashOperator(
        task_id="core_routed_task",
        bash_command=(
            "NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace) && "
            "echo \"Task=core_routed_task Namespace=$NAMESPACE Host=$(hostname)\""
        ),
        executor_config=CORE_EXECUTOR_CONFIG,
    )

    back_to_user_task = BashOperator(
        task_id="back_to_user_task",
        bash_command=(
            "NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace) && "
            "echo \"Task=back_to_user_task Namespace=$NAMESPACE Host=$(hostname)\""
        ),
    )

    default_user_task >> core_routed_task >> back_to_user_task

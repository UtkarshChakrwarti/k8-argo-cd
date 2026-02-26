"""
Example DAG: Tasks run in airflow-core namespace via executor_config override.

Uses pod_override in executor_config to explicitly target the airflow-core
namespace instead of the default airflow-user namespace. This requires
multi_namespace_mode=True in the KubernetesExecutor config.

Push this file to the remote_airflow repo under dags/ directory.
"""

from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator
from kubernetes.client import models as k8s

with DAG(
    dag_id="example_core_namespace",
    start_date=datetime(2024, 1, 1),
    schedule=None,
    catchup=False,
    tags=["namespace-demo", "airflow-core"],
    doc_md="""
    ## Namespace Demo: airflow-core

    This DAG demonstrates tasks running in the **airflow-core** namespace
    by using `executor_config` with `pod_override` to set the namespace.
    Requires `multi_namespace_mode=True` in KubernetesExecutor configuration.
    """,
):
    verify_namespace = BashOperator(
        task_id="verify_namespace",
        bash_command=(
            "echo '=== Task Pod Namespace Info ===' && "
            "NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace) && "
            "echo \"Running in namespace: $NAMESPACE\" && "
            "echo \"Hostname: $(hostname)\" && "
            "echo \"Date: $(date)\" && "
            "if [ \"$NAMESPACE\" = 'airflow-core' ]; then "
            "  echo 'PASS: Correctly running in airflow-core namespace'; "
            "else "
            "  echo \"WARN: Expected airflow-core but got $NAMESPACE\"; "
            "fi"
        ),
        executor_config={
            "pod_override": k8s.V1Pod(
                metadata=k8s.V1ObjectMeta(namespace="airflow-core"),
            ),
        },
    )

    run_task = BashOperator(
        task_id="run_sample_task",
        bash_command=(
            "echo 'Executing sample workload in airflow-core namespace...' && "
            "python3 -c \"import sys; print(f'Python {sys.version}')\" && "
            "echo 'Task completed successfully'"
        ),
        executor_config={
            "pod_override": k8s.V1Pod(
                metadata=k8s.V1ObjectMeta(namespace="airflow-core"),
            ),
        },
    )

    verify_namespace >> run_task

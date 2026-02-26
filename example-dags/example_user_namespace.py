"""
Example DAG: Tasks run in airflow-user namespace (default).

No executor_config override needed — KubernetesExecutor uses the default
namespace (airflow-user) configured via AIRFLOW__KUBERNETES_EXECUTOR__NAMESPACE.

Push this file to the remote_airflow repo under dags/ directory.
"""

from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    dag_id="example_user_namespace",
    start_date=datetime(2024, 1, 1),
    schedule=None,
    catchup=False,
    tags=["namespace-demo", "airflow-user"],
    doc_md="""
    ## Namespace Demo: airflow-user

    This DAG demonstrates tasks running in the **airflow-user** namespace.
    Task pods are created by KubernetesExecutor in the default target namespace.
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
            "if [ \"$NAMESPACE\" = 'airflow-user' ]; then "
            "  echo 'PASS: Correctly running in airflow-user namespace'; "
            "else "
            "  echo \"WARN: Expected airflow-user but got $NAMESPACE\"; "
            "fi"
        ),
    )

    run_task = BashOperator(
        task_id="run_sample_task",
        bash_command=(
            "echo 'Executing sample workload in airflow-user namespace...' && "
            "python3 -c \"import sys; print(f'Python {sys.version}')\" && "
            "echo 'Task completed successfully'"
        ),
    )

    verify_namespace >> run_task

# DevOps Operations Runbook

This runbook defines the expected behavior of the local GitOps setup and the standard repeatable workflow for daily development.

## 1. Repo Segregation (Source of Truth)

- GitOps manifests (ArgoCD sync source):
  - `https://github.com/UtkarshChakrwarti/k8-argo-cd.git`
- DAG source (pulled by in-cluster git-sync):
  - `https://github.com/UtkarshChakrwarti/remote_airflow.git` (`main`)
- Local workspace:
  - `Codespace_PLAY` is for development scripts, validation, and handoff YAML generation.

Runtime DAG loading is only from the remote DAG repo.

## 2. Namespace-First DAG Pattern

For DAG authors, keep namespace routing simple and DAG-level:

```python
from airflow_namespace_executor import namespace_executor_config

default_args = {
    "executor_config": namespace_executor_config("airflow-user"),
}
```

Use `airflow-user` or `airflow-core` based on where that entire DAG should run.

In-cluster runtime DAG path:
- `/home/airflow/dags/repo/dags`

## 3. Standard Full-Cycle Workflow

Use this whenever you want a clean end-to-end verification:

```bash
make dev-down
make dev-up
make status
```

`make dev-up` now performs:
1. Tool and repo access checks.
2. Cluster bootstrap (if needed).
3. ArgoCD app bootstrap/sync.
4. Hard refresh of Argo apps to avoid stale comparison state.
5. MySQL + Airflow + monitoring readiness wait (fail-fast on timeout).
6. Initial DAG unpause + one-time bootstrap trigger (only if no existing run is present).
7. Persistent port-forwards for Argo/Airflow/MySQL/Prometheus/Grafana.

Port-forward runtime files:
- PID/log directory: `.runtime/port-forward/`
- Cleared automatically by `make dev-down`.

## 4. Health Verification Checklist

Quick checks:

```bash
kubectl -n argocd get applications
kubectl -n airflow-core get deploy
kubectl -n airflow-core get pods
kubectl -n airflow-user get pods
```

Expected:
- Argo apps: `Synced` + `Healthy`
- Airflow core deployments: all `1/1`
- Demo DAGs visible:
  - `example_user_namespace`
  - `example_core_namespace`

## 5. Resource Tuning Baseline

Current Airflow control-plane baseline:

- `airflow-scheduler`: request `300m/768Mi`, limit `1200m/1536Mi`
- `airflow-webserver`: request `250m/512Mi`, limit `1000m/1Gi`
- `airflow-triggerer`: request `250m/512Mi`, limit `1000m/1Gi`
- `airflow-dag-processor`: request `200m/384Mi`, limit `800m/768Mi`

ReplicaSet churn control:
- All primary deployments use `revisionHistoryLimit: 1`.

## 6. Troubleshooting

If DAGs are missing in UI:
1. Check git-sync logs:
   - `kubectl -n airflow-core logs deploy/airflow-dag-sync -c git-sync --tail=100`
2. Confirm runtime DAG repo config:
   - `kubectl -n airflow-core get cm airflow-config -o jsonpath='{.data.DAG_GIT_SYNC_REPO}{"\\n"}{.data.DAG_GIT_SYNC_REF}{"\\n"}'`
3. Confirm parser/scheduler pods are healthy.

If logs fail in Airflow UI:
1. Confirm webserver/scheduler RBAC in `airflow-user`.
2. Confirm custom logging ConfigMap is mounted in webserver/scheduler/triggerer/dag-processor.

If localhost UIs are not reachable:
1. Start port-forwards manually in separate terminals:
   - `make argocd-port-forward`
   - `make airflow-port-forward`
   - `make prometheus-port-forward`
   - `make grafana-port-forward`
2. Verify listeners:
   - `lsof -nP -iTCP:8080,8090,9090,3000,3306 -sTCP:LISTEN`

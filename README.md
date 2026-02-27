# Airflow 3.0 Multi-Namespace GitOps on Kind

A Kubernetes-native Airflow 3.0.0 stack managed with Argo CD (App-of-Apps) on a local Kind cluster.

## Architecture

- Cluster: Kind (`gitops-poc`)
- GitOps: Argo CD (`root-app` + child apps)
- Airflow control plane namespace: `airflow-core`
- Airflow task namespace: `airflow-user` (default for `KubernetesExecutor`)
- Kind node pools:
  - `workload=airflow-core` + taint `dedicated=airflow-core:NoSchedule` (Airflow control-plane + core-routed tasks)
  - `workload=airflow-user` + taint `dedicated=airflow-user:NoSchedule` (default task pods)
- Database: MySQL (`mysql` namespace)
- Observability stack in `airflow-core`:
  - kube-state-metrics
  - Prometheus
  - Grafana

## Quick Start

```bash
make dev-up
```

This creates the cluster, installs Argo CD, bootstraps applications, and starts local port-forwards.

## Local Endpoints

- Argo CD: `https://localhost:8080` (admin/admin)
- Airflow: `http://localhost:8090` (admin/admin)
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000` (admin/admin)
  - Default dashboard: `Airflow Kubernetes Overview`
- MySQL: `127.0.0.1:3306`

Credentials are written to:
- `.argocd-credentials.txt`
- `.airflow-credentials.txt`
- `.mysql-credentials.txt`

## Namespace Behavior

- Control plane pods run in `airflow-core`:
  - scheduler, webserver, triggerer, dag-processor, dag-sync
- Task pods run in `airflow-user` by default.
- DAGs can override task namespace via `executor_config` and switch to `airflow-core` when needed.

## DAGs Included

- DAG source repo: `https://github.com/UtkarshChakrwarti/remote_airflow.git` (`main`, path `dags/`)
- Included examples:
  - `example_user_namespace`: one task, prints runtime namespace (manual trigger)
  - `example_core_namespace`: one task, same print with namespace override (manual trigger)
- `make dev-up` unpauses both demo DAGs and triggers each only if no prior run exists.
- DAGs are always pulled from `remote_airflow` (`DAG_GIT_SYNC_REPO` + `DAG_GIT_SYNC_REF`), not from this repo.
- Worker pods are retained (`DELETE_WORKER_PODS=False`) to keep Airflow task log links stable.
- Task log handler uses Kubernetes pod-log fallback, and webserver has cross-namespace RBAC to read task pod logs in both namespaces.

Namespace-first DAG authoring (no K8s object boilerplate):

```python
from airflow_namespace_executor import namespace_executor_config

default_args = {
    "executor_config": namespace_executor_config("airflow-core"),
}
```

Set `executor_config` once in `default_args` so the full DAG runs in that namespace.
Namespace alone is enough: a pod mutation hook maps `airflow-core` to the core node pool and `airflow-user` to the user node pool automatically.

## Repo Roles

- Manifests/GitOps repo used by Argo CD: `https://github.com/UtkarshChakrwarti/k8-argo-cd.git`
- DAG code repo pulled by git-sync: `https://github.com/UtkarshChakrwarti/remote_airflow.git`
- `Codespace_PLAY` is local dev workspace; runtime DAG loading does not come from local files.

## Common Commands

- `make status` - show component status and namespaces
- `make logs` - tail key logs
- `make sanity` - run manifest + repo sanity checks
- `make validate` - validate all kustomize outputs
- `make argocd-port-forward` - start Argo CD port-forward
- `make airflow-port-forward` - start Airflow port-forward
- `make prometheus-port-forward` - start Prometheus port-forward
- `make grafana-port-forward` - start Grafana port-forward
- `make dev-down` - tear down everything

## Scaling Reference

See [docs/airflow-scaling-and-capacity.md](docs/airflow-scaling-and-capacity.md) for current sizing, executor behavior, and scaling strategy.

## Ops Runbook

See [docs/devops-operations-runbook.md](docs/devops-operations-runbook.md) for full cycle (`make dev-down` / `make dev-up`) behavior, verification checklist, and troubleshooting.

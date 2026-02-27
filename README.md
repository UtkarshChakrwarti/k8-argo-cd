# Airflow 3.0 Multi-Namespace GitOps on Kind

A Kubernetes-native Airflow 3.0.0 stack managed with Argo CD (App-of-Apps) on a local Kind cluster.

## Architecture

- Cluster: Kind (`gitops-poc`)
- GitOps: Argo CD (`root-app` + child apps)
- Airflow control plane namespace: `airflow-core`
- Airflow task namespace: `airflow-user` (default for `KubernetesExecutor`)
- Kind node pools:
  - `airflow-node-pool=core` (Airflow control-plane + core-routed tasks)
  - `airflow-node-pool=user` + taint `dedicated=airflow-user:NoSchedule` (default task pods)
- Database: MySQL (`mysql` namespace)
- Observability stack in `airflow-core`:
  - kube-ops-view
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
- Monitoring (pods/nodes/workloads): `http://localhost:8091`
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

- DAG source path for git-sync: `dags/`
- Included examples:
  - `dags/example_user_namespace.py`: default tasks in `airflow-user`
  - `dags/example_core_namespace.py`: tasks forced to `airflow-core` with `executor_config`
  - `dags/example_mixed_namespace.py`: one DAG running tasks in both namespaces

## Common Commands

- `make status` - show component status and namespaces
- `make logs` - tail key logs
- `make sanity` - run manifest + repo sanity checks
- `make validate` - validate all kustomize outputs
- `make argocd-port-forward` - start Argo CD port-forward
- `make airflow-port-forward` - start Airflow port-forward
- `make monitoring-port-forward` - start monitoring UI port-forward
- `make prometheus-port-forward` - start Prometheus port-forward
- `make grafana-port-forward` - start Grafana port-forward
- `make dev-down` - tear down everything

## Scaling Reference

See [docs/airflow-scaling-and-capacity.md](docs/airflow-scaling-and-capacity.md) for current sizing, executor behavior, and scaling strategy.

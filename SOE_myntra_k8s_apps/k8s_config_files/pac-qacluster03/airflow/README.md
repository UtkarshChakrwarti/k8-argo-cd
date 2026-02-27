# Airflow YAML Pack (pac-qacluster03)

This folder is a handoff-ready YAML set for Argo CD users.

## Apply with Argo CD

Point your Argo CD Application source to:

- `SOE_myntra_k8s_apps/k8s_config_files/pac-qacluster03/airflow`

You can use [90-argocd-application-template.yaml](90-argocd-application-template.yaml) as a base template.

## Contents

- `kustomization.yaml`: bundles all manifests in order (Argo CD/Kustomize entrypoint)
- `01..13`: Airflow multi-namespace control-plane + executor manifests
- `14-monitoring-kube-ops-view.yaml`: workload topology UI in `airflow-core`
- `15-kube-state-metrics.yaml`: kube-state-metrics exporter
- `16-prometheus.yaml`: Prometheus server + config + RBAC
- `17-grafana.yaml`: Grafana + Prometheus datasource + preloaded pod/resource dashboard

## Notes

- Control-plane namespace: `airflow-core`
- Task namespace: `airflow-user`
- Monitoring/observability is not in a separate namespace; it runs in `airflow-core`
- Node routing:
  - Control-plane pods and core-routed tasks use `nodeSelector: airflow-node-pool=core`
  - Default user tasks use `nodeSelector: airflow-node-pool=user` + toleration `dedicated=airflow-user:NoSchedule`
- DAG repo sync source is controlled by `DAG_GIT_SYNC_REPO` and `DAG_GIT_SYNC_REF` in `04-configmaps-airflow.yaml`
- New DAGs are auto-unpaused (`AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=False`) so scheduled DAGs start without manual unpause.
- DAG sync resilience:
  - Continuous sync uses `--link=repo` with atomic switch to new revision.
  - If pull/fetch fails, old DAG files stay in place (last-good revision is preserved).
  - `--max-failures=-1` keeps retrying forever.
  - `--stale-worktree-timeout=5m` cleans stale temporary worktrees.
- Worker pods are retained (`DELETE_WORKER_PODS=False`) to keep Airflow task log links stable.

# Airflow Scaling and Capacity Reference

This file documents the current runtime sizing and scaling behavior for this repository.

## 1. Current Control Plane Sizing

Source of truth:
- `k8s/airflow/overlays/dev/kustomization.yaml` (replica counts)
- `k8s/airflow/base/*-deployment.yaml` (resources)
- `k8s/airflow/base/configmap.yaml` (Airflow runtime config)

Current replicas (dev overlay):
- `airflow-webserver`: 1
- `airflow-scheduler`: 1
- `airflow-triggerer`: 1
- `airflow-dag-processor`: 1
- `airflow-dag-sync`: 1

Current CPU/Memory:
- `airflow-scheduler`: request `300m/768Mi`, limit `1200m/1536Mi`
- `airflow-webserver`: request `250m/512Mi`, limit `1000m/1Gi`
- `airflow-triggerer`: request `250m/512Mi`, limit `1000m/1Gi`
- `airflow-dag-processor`: request `200m/384Mi`, limit `800m/768Mi`
- `airflow-dag-sync`: request `50m/32Mi`, limit `200m/128Mi`
- `airflow-db-migrate` job: request `250m/512Mi`, limit `1000m/1Gi`

## 2. Task Pod Sizing (KubernetesExecutor)

Source: `k8s/airflow/base/configmap.yaml` -> `airflow-pod-template`

Default task pod (`airflow-user`) and override template (`airflow-core`) both use:
- request `200m/256Mi`
- limit `1000m/512Mi`

Namespace behavior:
- Default task namespace: `airflow-user`
- Multi-namespace enabled: `airflow-core,airflow-user`
- DAG-level override available through `executor_config` using helper:
  - `from airflow_namespace_executor import namespace_executor_config`
  - `default_args["executor_config"] = namespace_executor_config("airflow-core")`

Node pool behavior:
- Default user tasks use pod template `pod_template_user.yaml`:
  - `nodeSelector: airflow-node-pool=user`
  - toleration `dedicated=airflow-user:NoSchedule`
- Core-routed tasks use pod template `pod_template_core.yaml`:
  - `nodeSelector: airflow-node-pool=core`

## 3. Airflow Runtime Throughput Settings

Source: `k8s/airflow/base/configmap.yaml`

- `AIRFLOW__CORE__PARALLELISM=200`
- `AIRFLOW__KUBERNETES_EXECUTOR__WORKER_PODS_CREATION_BATCH_SIZE=1`
- `AIRFLOW__SCHEDULER__STANDALONE_DAG_PROCESSOR=True`
- DB pool:
  - `AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_SIZE=20`
  - `AIRFLOW__DATABASE__SQL_ALCHEMY_MAX_OVERFLOW=10`
  - `AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_TIMEOUT=90`

## 4. Autoscaling Status (Current)

Currently there is no HPA/VPA configured for Airflow components.

What scales automatically today:
- Task pods scale with workload because KubernetesExecutor creates one pod per runnable task.

What does not autoscale:
- Scheduler/Webserver/Triggerer/Dag-Processor/Dag-Sync replica counts
- CPU/memory requests/limits

## 5. Manual Scaling Playbook

Scale control-plane replicas in:
- `k8s/airflow/overlays/dev/kustomization.yaml` -> `replicas:`

Tune task throughput in:
- `k8s/airflow/base/configmap.yaml`

Recommended trigger points:
- Increase scheduler resources/replicas if queued tasks stay high for 10+ minutes.
- Increase `WORKER_PODS_CREATION_BATCH_SIZE` if task start latency is high and cluster has spare capacity.
- Increase DB pool settings if scheduler logs show DB pool timeouts.
- Increase task pod requests/limits if tasks are OOMKilled or throttled.

## 6. Safe Scaling Sequence

1. Increase scheduler CPU/memory first.
2. Increase `WORKER_PODS_CREATION_BATCH_SIZE` gradually (for example: `1 -> 5 -> 10`).
3. Increase task pod requests/limits only for DAGs that need it.
4. Re-check MySQL load before further throughput increases.

## 7. Observability Endpoints

- Airflow UI: `http://localhost:8090`
- Argo CD: `https://localhost:8080`
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000` (admin/admin)
- Grafana default dashboard: `Airflow Kubernetes Overview`

## 8. DAG Sync Source and Failure Behavior

Source:
- DAG repo URL: `https://github.com/UtkarshChakrwarti/remote_airflow.git`
- DAG repo ref/branch/tag: `main`
- DAG path inside repo: `/dags`

Failure behavior:
- `--max-failures=-1` retries forever.
- `--link=repo` keeps serving last-good revision atomically.
- `--stale-worktree-timeout=5m` prunes stale temporary worktrees.
- `--sync-timeout=2m` bounds each sync attempt.

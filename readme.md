# GitOps POC — Local Kubernetes + Argo CD + Airflow 3.0 + MySQL

A fully local GitOps stack running inside a **Kind** (Kubernetes-in-Docker) cluster.  
Argo CD watches a **local git daemon** (no GitHub required) and continuously deploys
Apache Airflow 3.0.0 and MySQL 8.0.

```
┌─────────────────────────── Kind Cluster ─────────────────────────────────┐
│                                                                            │
│  ┌──────────────┐   GitOps sync   ┌────────────────────────────────────┐  │
│  │   Argo CD    │◄────────────────│  Local git daemon  :9418           │  │
│  │  (argocd ns) │                 │  (serves ./  on the host)          │  │
│  └──────┬───────┘                 └────────────────────────────────────┘  │
│         │ deploys                                                          │
│  ┌──────▼──────────────────────────────────────────────┐                  │
│  │  Airflow 3.0.0 (KubernetesExecutor)   namespace: airflow               │
│  │   api-server  │  scheduler  │  triggerer             │                  │
│  │   dag-sync sidecar ──► /dags-host (host dags/ mount)│                  │
│  └──────────────────────────────────────────────────────┘                 │
│  ┌──────────────────────────┐                                             │
│  │  MySQL 8.0  (mysql ns)   │◄── Airflow metadata DB                     │
│  └──────────────────────────┘                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# 1. Start everything
make dev-up

# 2. Open UIs (credentials in .airflow-credentials.txt)
make airflow-ui    # http://localhost:8090  (admin user)
make argocd-ui     # https://localhost:8080

# 3. Check health
make status

# 4. Tear down
make dev-down
```

## DAG Sync (local → cluster)

Edit or add `.py` files in `dags/` — the `dag-sync` sidecar (rsync + inotify)
picks up changes within **10 seconds** and syncs them into every Airflow pod.

```
dags/
├── hello_world_dag.py    ← simple hello-world example
└── load_testing_dag.py   ← CPU / memory / I-O load test
```

## Architecture

| Component | Image | Port |
|-----------|-------|------|
| Airflow api-server | `apache/airflow:3.0.0-python3.12` | 8090 (host) |
| Airflow scheduler | same | — |
| Airflow triggerer | same | — |
| MySQL | `mysql:8.0` | internal |
| Argo CD | stable | 8080 (host, HTTPS) |
| dag-sync sidecar | `dag-sync:local` (Alpine rsync + inotify) | — |

## Prerequisites

`docker`, `kubectl`, `kind`, `argocd` CLI, `python3` (with `cryptography` package)

```bash
make install-prereqs
```

## Makefile targets

| Target | Description |
|--------|-------------|
| `make dev-up` | Create cluster, install all services |
| `make dev-down` | Delete cluster, stop git daemon |
| `make status` | Health check for all components |
| `make logs` | Tail logs for all services |
| `make build-dag-sync` | Rebuild & reload dag-sync image |
| `make validate` | Validate kustomize manifests |

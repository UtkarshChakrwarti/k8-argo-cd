# Getting Started with the CI/CD + GitOps POC

## 🚀 Quick Start (2 minutes)

### Option 1: One-Command Setup

```bash
make dev-up
```

This will:
1. ✅ Check prerequisites (Docker, kubectl, kind, argocd)
2. ✅ Create a local Kubernetes cluster using kind
3. ✅ Install Argo CD for GitOps automation
4. ✅ Install MySQL 8.0 database
5. ✅ Deploy Apache Airflow 3.0.1 with KubernetesExecutor
6. ✅ Bootstrap GitOps Applications for automatic reconciliation

### Option 2: Interactive Setup

```bash
./QUICKSTART.sh
```

## 📊 After Setup: Key Commands

```bash
# Check component status
make status

# Open Argo CD (port-forward + browser)
make argocd-ui

# Open Airflow UI (port-forward + browser)  
make airflow-ui

# View logs from all services
make logs

# Tear down environment
make dev-down

# Get help
make help
```

## 📁 What Was Created

```
✓ Kubernetes Manifests (k8s/):
  ├── MySQL:  base/ + overlays/dev/
  │   ├── StatefulSet with persistent storage (PVC)
  │   ├── Service (headless)
  │   ├── ConfigMap with init script
  │   └── Secrets (root + airflow passwords)
  │
  ├── Airflow: base/ + overlays/dev/
  │   ├── Deployments: webserver, scheduler, triggerer
  │   ├── ServiceAccount with RBAC for KubernetesExecutor
  │   ├── ConfigMap with Airflow settings
  │   ├── Jobs: db-migrate (PreSync), create-admin (PostSync)
  │   └── Secrets (SQL_ALCHEMY_CONN, FERNET_KEY, etc.)
  │
  └── Argo CD: Applications app-of-apps pattern
      ├── root-app (orchestrator)
      ├── mysql-app (child)
      └── airflow-app (child)

✓ Bootstrap Scripts (scripts/):
  ├── dev-up.sh               (13KB | Full setup orchestration)
  ├── dev-down.sh             (Cleanup)
  ├── status.sh               (Component health check)
  ├── argocd-port-forward.sh  (Access Argo CD UI)
  └── airflow-port-forward.sh (Access Airflow UI)

✓ Management (Makefile):
  ├── dev-up              Create full environment
  ├── dev-down            Tear down everything
  ├── status              Show component health
  ├── argocd-ui           Open UI
  ├── airflow-ui          Open UI
  ├── logs                Tail all logs
  ├── validate            Check manifest syntax
  └── help                Show all targets

✓ Documentation:
  ├── GITOPS_POC_README.md    (Full architecture & troubleshooting)
  ├── SETUP.md                (This file)
  └── QUICKSTART.sh           (Interactive setup)
```

## 🔑 Credentials (Auto-Generated)

After `make dev-up`, credentials are saved securely:

### `.mysql-credentials.txt`
```
MYSQL_ROOT_PASSWORD=<base64-random>
AIRFLOW_DB_PASSWORD=<base64-random>
```

### `.airflow-credentials.txt`
```
AIRFLOW_ADMIN_PASSWORD=<base64-random>
AIRFLOW_FERNET_KEY=<base64-fernet>
AIRFLOW_WEBSERVER_SECRET_KEY=<base64-random>
SQL_ALCHEMY_CONN=mysql+pymysql://airflow:PASSWORD@...
```

**⚠️ WARNING**: These files are NOT committed to git. They contain secrets only in the local cluster.

## 🌐 Service URLs (after port-forward)

| Service | URL | Port |
|---------|-----|------|
| **Argo CD** | https://localhost:8080 | 443 → 8080 |
| **Airflow** | http://localhost:8090 | 8080 → 8090 |
| **MySQL** | localhost:3306 (internal) | 3306 |

## ⚙️ Architecture at a Glance

```
GitHub Repo (GitOps)
         ↓
    [dev-up.sh]
         ↓
  kind cluster
    ├─ Argo CD (watches repo)
    ├─ MySQL StatefulSet
    └─ Airflow
        ├─ Webserver (UI)
        ├─ Scheduler (runs DAGs)
        ├─ Triggerer (async events)
        └─ KubernetesExecutor (task pods)
```

## ✅ Prerequisites Checklist

Before running `make dev-up`:

- [ ] Docker running (`docker info`)
- [ ] kubectl installed (`kubectl version --client`)
- [ ] kind installed (`kind version`)
- [ ] argocd CLI installed (`argocd version`)
- [ ] Python 3.x (`python3 --version`)
- [ ] bash/sh + standard Unix tools

**Auto-install missing tools:**

```bash
make install-prereqs
```

## 🔄 GitOps Workflow

1. **Modify K8s manifests** in `k8s/airflow/` or `k8s/mysql/`
2. **Commit & push** to GitHub: `git add . && git commit -m "..." && git push`
3. **Argo CD detects changes** within ~3 minutes
4. **Cluster auto-syncs** → new resources deployed

Or manually sync:
```bash
argocd app sync mysql-app
argocd app sync airflow-app
```

## 🧪 Quick Test: Deploy a DAG

1. Create a DAG file:
   ```bash
   mkdir -p dags
   cat > dags/hello.py << 'EOF'
   from airflow import DAG
   from airflow.operators.bash import BashOperator
   from datetime import datetime

   dag = DAG('hello_dag', start_date=datetime(2024, 1, 1))
   task = BashOperator(task_id='hello', bash_command='echo Hello Airflow!', dag=dag)
   EOF
   ```

2. Commit: `git add dags/hello.py && git commit -m "Add hello DAG" && git push`

3. Wait ~3 min for Argo CD sync, then:
   ```bash
   make airflow-ui
   ```

4. Access Airflow, enable DAG, trigger manually

## 📝 Common Issues & Fixes

| Issue | Solution |
|-------|----------|
| "kind not found" | `make install-prereqs` |
| "Cluster already exists" | `make dev-down` then `make dev-up` |
| Airflow not ready after 5 min | `make logs` and check Pod events |
| Services not accessible | Verify port-forward: `make <service>-ui` |
| DB connection failed | Check MySQL logs: `kubectl logs -n mysql -l app=mysql` |
| Secrets not found | Manually create: See `scripts/dev-up.sh` |

## 📚 Full Documentation

See [GITOPS_POC_README.md](GITOPS_POC_README.md) for:
- Complete architecture diagram
- Detailed configuration options
- Advanced scaling & customization
- Troubleshooting guide
- References & links

## 🎯 What to Explore

### 1. Argo CD GitOps in Action
```bash
make argocd-ui
# View Applications → mysql-app, airflow-app
# See automatic sync and Pod status
```

### 2. Airflow KubernetesExecutor
```bash
make airflow-ui
# Login: admin / (check .airflow-credentials.txt)
# Create a test DAG and trigger
# Watch task pods spawn/run/delete in airflow namespace
```

### 3. MySQL Persistence
```bash
kubectl get pvc -n mysql
kubectl describe pvc mysql-pvc -n mysql
```

### 4. Inspect Manifests
```bash
kustomize build k8s/airflow/overlays/dev
kustomize build k8s/mysql/overlays/dev
```

## 🛑 Shutdown

```bash
make dev-down
```

This deletes the kind cluster completely. Credentials files are removed.

## 💡 Next Steps

- [ ] Review Airflow DAG documentation: https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/dags.html
- [ ] Learn Argo CD: https://argo-cd.readthedocs.io/
- [ ] Customize Airflow image (add Python packages) in a Dockerfile
- [ ] Deploy to a real cluster (EKS, GKE, AKS) by updating REPO_URL
- [ ] Set GitOps branching strategy (dev → staging → prod)

---

**Ready?** Start with:
```bash
make dev-up
```

Questions or issues? Check [GITOPS_POC_README.md](GITOPS_POC_README.md).

# GitOps POC: CI/CD + Kubernetes + Airflow

A complete local CI/CD + GitOps proof-of-concept built on Kubernetes (kind), Argo CD, MySQL 8.0, and Apache Airflow 3.0.1 with KubernetesExecutor in a GitHub Codespace.

## Architecture

```
┌─────────────────────────────────────┐
│     Kind Cluster (gitops-poc)       │
├─────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐ │
│  │   Argo CD    │  │ ingress-nginx│ │
│  │  (argocd ns) │  │              │ │
│  └──────────────┘  └──────────────┘ │
│        │                             │
│        ├─────────────┬───────────────┤
│        │             │               │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐
│  │  MySQL   │  │ Airflow  │  │ Task Pods  │
│  │(mysql ns)│  │(airflow) │  │(KubeExec)  │
│  └──────────┘  └──────────┘  └────────────┘
│     StatefulSet      ├─ Webserver
│     PVC              ├─ Scheduler
│                      ├─ Triggerer
└─────────────────────────────────────┘
         ▲
         │ GitOps
         │ (Argo CD watches repo)
         │
    [GitHub Repo]
    k8s/mysql/overlays/dev
    k8s/airflow/overlays/dev
```

## Prerequisites

The following must be installed before running the setup:

- **Docker**: Available in Codespaces by default
- **kubectl**: Kubernetes CLI
- **kind**: Kubernetes in Docker for cluster creation
- **argocd**: Argo CD CLI for management
- **kustomize**: For manifest templating
- **Python 3**: For secret generation

### Quick Install (Codespaces)

For Codespaces, most tools are pre-installed. Verify with:

```bash
docker --version
kubectl version --client
kind version
argocd version
kustomize version
python3 --version
```

If any tools are missing, run:

```bash
make install-prereqs
```

## Quick Start

### 1. Start the Environment

```bash
make dev-up
```

This will:
- Check prerequisites
- Create a kind cluster (1 control-plane + 1 worker node)
- Install ingress-nginx  
- Install Argo CD
- Create MySQL and Airflow namespaces
- Create secrets for MySQL and Airflow
- Bootstrap Argo CD Applications for GitOps
- Wait for all services to be ready

**Expected output:**
```
[INFO] Starting GitOps POC setup...
[SUCCESS] All required tools found
[SUCCESS] Resolved REPO_URL: https://github.com/UtkarshChakrwarti/Codespace_PLAY.git
[SUCCESS] Kind cluster created successfully
[SUCCESS] ingress-nginx installed successfully
[SUCCESS] Argo CD installed successfully
[SUCCESS] Created namespace 'mysql'
[SUCCESS] Created namespace 'airflow'
[SUCCESS] MySQL secret created
[SUCCESS] Airflow secret created
[SUCCESS] Argo CD root app bootstrapped
[SUCCESS] GitOps POC setup completed successfully!
```

Credentials are saved to:
- `.mysql-credentials.txt` – MySQL root and airflow DB passwords
- `.airflow-credentials.txt` – Airflow admin credentials and secrets

### 2. Access the UIs

Open Argo CD:
```bash
make argocd-ui
```

Open Airflow:
```bash
make airflow-ui
```

Or manually port-forward:

```bash
# Argo CD (8080 → 443)
make argocd-port-forward

# Airflow (8090 → 8080)
make airflow-port-forward
```

Then in your browser:
- **Argo CD**: https://localhost:8080
- **Airflow**: http://localhost:8090

### 3. Check Status

```bash
make status
```

Shows readiness of all components (Argo CD, MySQL, Airflow).

### 4. Review Logs

```bash
make logs
```

Shows recent logs from all services.

### 5. Cleanup

```bash
make dev-down
```

Deletes the kind cluster completely.

## Directory Structure

```
.
├── Makefile                 # Management targets
├── k8s/
│   ├── apps/               # Argo CD Applications
│   │   ├── app-of-apps.yaml    # Root application
│   │   ├── mysql-app.yaml      # MySQL child app
│   │   ├── airflow-app.yaml    # Airflow child app
│   │   └── kustomization.yaml
│   ├── mysql/
│   │   ├── base/
│   │   │   ├── kustomization.yaml
│   │   │   ├── pvc.yaml
│   │   │   ├── configmap.yaml
│   │   │   ├── service.yaml
│   │   │   └── statefulset.yaml
│   │   └── overlays/dev/
│   │       └── kustomization.yaml
│   └── airflow/
│       ├── base/
│       │   ├── kustomization.yaml
│       │   ├── serviceaccount.yaml
│       │   ├── configmap.yaml
│       │   ├── migrate-job.yaml
│       │   ├── create-admin-job.yaml
│       │   ├── webserver-deployment.yaml
│       │   ├── scheduler-deployment.yaml
│       │   ├── triggerer-deployment.yaml
│       │   └── webserver-service.yaml
│       └── overlays/dev/
│           └── kustomization.yaml
└── scripts/
    ├── dev-up.sh              # Bootstrap entire environment
    ├── dev-down.sh            # Tear down environment
    ├── status.sh              # Show component status
    ├── argocd-port-forward.sh # Port-forward Argo CD
    └── airflow-port-forward.sh # Port-forward Airflow
```

## Configuration

### MySQL

- **Image**: `mysql:8.0`
- **Storage**: 10Gi PVC
- **Namespace**: `mysql`
- **Service**: `mysql.mysql.svc.cluster.local:3306` (headless)
- **Init**: Runs SQL script to:
  - Create `airflow` database
  - Create `airflow` user
  - Grant all privileges

### Airflow

- **Image**: `apache/airflow:3.0.1-python3.12`
- **Executor**: `KubernetesExecutor`
- **Namespace**: `airflow`
- **Components**:
  - **Webserver**: HTTP API and UI on port 8080
  - **Scheduler**: DAG scheduling and execution
  - **Triggerer**: Async event handling (Airflow 3.0 requirement)
  - **Task Pods**: Per-task execution via KubernetesExecutor

### Argo CD

- **Namespace**: `argocd`
- **UI**: HTTPS on port 443 (port-forward to 8080)
- **GitOps**: Watches this repository's `k8s/apps` and child apps
- **Sync Policy**: Automated with prune and self-heal enabled

## Credentials

After `make dev-up`, credentials are saved locally:

### MySQL (.mysql-credentials.txt)
```
MYSQL_ROOT_PASSWORD=<random-base64>
AIRFLOW_DB_PASSWORD=<random-base64>
```

### Airflow (.airflow-credentials.txt)
```
AIRFLOW_FERNET_KEY=<base64-encoded-fernet-key>
AIRFLOW_WEBSERVER_SECRET_KEY=<random-base64>
AIRFLOW_ADMIN_PASSWORD=<random-base64>
SQL_ALCHEMY_CONN=mysql+pymysql://airflow:PASSWORD@mysql.mysql.svc.cluster.local:3306/airflow
```

**⚠️ Important**: These files are local only and NOT committed to git. They are secrets in the cluster.

## Accessing Services

### Argo CD

**Default credentials**:
- Username: `admin`
- Password: Get from Argo CD secret:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  ```

Or, set custom password by editing the secret.

### Airflow

**Admin credentials**:
- Username: `admin`
- Password: Check `.airflow-credentials.txt` → `AIRFLOW_ADMIN_PASSWORD`

Access at: http://localhost:8090

## Troubleshooting

### 1. "Cluster already exists" error

The kind cluster `gitops-poc` already exists. To recreate:

```bash
make dev-down
make dev-up
```

### 2. Port already in use (8080, 8090, 80, 443)

Change port mappings in `k8s/mysql/base/kustomization.yaml` or run:

```bash
# Use different ports
ARGOCD_PORT=8081 make argocd-port-forward
AIRFLOW_PORT=8091 make airflow-port-forward
```

### 3. Services not ready after `dev-up`

Wait a bit longer; Airflow components take time to initialize. Check:

```bash
make status
make logs
```

### 4. Database connection errors in Airflow

Verify MySQL is running:

```bash
kubectl get pods -n mysql
kubectl logs -n mysql -l app=mysql --tail=50
```

Verify the secret:

```bash
kubectl get secret airflow-secret -n airflow -o yaml
```

### 5. Restore deleted pods / failed reconciliation

Argo CD auto-syncs due to configured sync policy. Check app status:

```bash
kubectl get applications -n argocd -o wide
argocd app list
```

If stuck, manually sync:

```bash
argocd app sync mysql-app
argocd app sync airflow-app
```

### 6. "kind not found" error

Install kind:

```bash
go install sigs.k8s.io/kind@latest
```

Or on macOS:

```bash
brew install kind
```

### 7. Modify manifests and let GitOps handle it

1. Edit files in `k8s/mysql/` or `k8s/airflow/`
2. Commit to GitHub: `git add . && git commit -m "..." && git push`
3. Argo CD syncs automatically (within ~3 minutes by default)
4. Check: `kubectl get pods -n airflow` or `make status`

## Building DAGs

Add DAG files to `dags/` folder in this repository:

```
dags/
├── hello_world.py
├── example_dag.py
└── ...
```

Airflow scheduler automatically discovers DAGs. Access DAGs at:
- **Airflow UI**: http://localhost:8090/dags
- **Logs**: `kubectl logs -n airflow deployment/airflow-scheduler --tail=100`

## Testing a DAG Run

1. Access Airflow UI: http://localhost:8090
2. Login: `admin` / (password from `.airflow-credentials.txt`)
3. Enable a DAG by clicking the toggle
4. Trigger manually or wait for scheduled run
5. View task logs in UI or via kubectl:

```bash
kubectl get pods -n airflow -l dag_id=<dag_name>
kubectl logs -n airflow pod/<pod_name>
```

## GitOps Workflow

### Automatic Sync (Default)

1. Modify `k8s/mysql/` or `k8s/airflow/` files
2. Commit and push to GitHub
3. Argo CD detects changes within ~3 minutes
4. Cluster syncs automatically → new pods/configs deployed

### Manual Sync

```bash
argocd app sync mysql-app
argocd app sync airflow-app
```

Or via Argo CD UI.

## Advanced: Scaling and Customization

### Scale Airflow Scheduler

Edit `k8s/airflow/overlays/dev/kustomization.yaml`:

```yaml
replicas:
  - name: airflow-scheduler
    count: 3  # Scale to 3 replicas
```

### Customize Airflow Configuration

Edit `k8s/airflow/base/configmap.yaml` to add/modify env vars.

### Add Custom Python Packages

Create a custom Dockerfile:

```dockerfile
FROM apache/airflow:3.0.1-python3.12
RUN pip install --no-cache-dir <package-name>
```

Push to a registry and update image in `webserver-deployment.yaml`, etc.

## Cleanup and Reset

### Soft Reset (keep cluster)

```bash
make clean  # Remove local credential files
```

### Hard Reset (delete everything)

```bash
make dev-down
make dev-up  # Start fresh
```

## Known Limitations

1. **No persistent DAGs**: Task pods use emptyDir; DAGs must be synced from the repo. For persistent DAGs, mount a shared volume (e.g., NFS).

2. **No ingress configured**: Port-forwarding is used for access. For production, configure ingress-nginx.

3. **Single MySQL replica**: No HA. For production, use managed MySQL (RDS, Cloud SQL, etc.).

4. **Local cluster**: Data is lost if the cluster is recreated.

## Summary of Make Targets

| Target | Purpose |
|--------|---------|
| `make dev-up` | Create cluster + install all services |
| `make dev-down` | Delete cluster completely |
| `make status` | Show component readiness |
| `make argocd-ui` | Open Argo CD in browser |
| `make airflow-ui` | Open Airflow in browser |
| `make logs` | Show logs from all services |
| `make validate` | Validate k8s manifests |
| `make clean` | Remove credential files |
| `make help` | Show all targets |

## References

- **Argo CD**: https://argo-cd.readthedocs.io/
- **Apache Airflow**: https://airflow.apache.org/docs/
- **Kubernetes**: https://kubernetes.io/docs/
- **kind**: https://kind.sigs.k8s.io/
- **Kustomize**: https://kustomize.io/

## License

This POC is provided as-is for educational and development purposes.

# 🚀 CI/CD + GitOps POC - Complete Setup

A complete **Proof of Concept** for a modern CI/CD and GitOps infrastructure built on Kubernetes with Argo CD, MySQL, and Apache Airflow 3.0.1 running in GitHub Codespaces.

## 📋 Table of Contents

- [Overview](#overview)
- [What's Included](#whats-included)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Accessing the Services](#accessing-the-services)
- [Project Structure](#project-structure)
- [Configuration Details](#configuration-details)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

---

## 🎯 Overview

This POC demonstrates a complete containerized, GitOps-driven infrastructure with:

- **Kubernetes (kind)**: Local Kubernetes cluster with 2 nodes (control-plane + worker)
- **Argo CD**: GitOps automation with app-of-apps pattern and automated sync
- **MySQL 8.0**: Persistent database backend with PVC storage
- **Apache Airflow 3.0.1**: Distributed task orchestration with KubernetesExecutor
- **Infrastructure as Code**: All components defined in YAML using Kustomize overlays
- **Automated Deployment**: Shell scripts and Makefile targets for easy management

**Status**: ✅ Fully operational and accessible via port forwarding

---

## 📦 What's Included

### Core Components

| Component | Version | Status | Purpose |
|-----------|---------|--------|---------|
| Kubernetes | 1.35.0 (kind) | ✅ Running | Container orchestration platform |
| Argo CD | v3.3.2 | ✅ Running (7 pods) | GitOps automation and sync |
| MySQL | 8.0 | ✅ Running (StatefulSet) | Metadata database for Airflow |
| Apache Airflow | 3.0.1 | 🔄 Initializing | Task orchestration engine |
| Docker | Latest | ✅ Pre-installed | Container runtime |

### Infrastructure Files

- **20+ Kubernetes manifests** organized by component (MySQL, Airflow, Argo CD apps)
- **Kustomize overlays** for environment-specific configurations (dev/staging/prod ready)
- **5 automation scripts** for cluster management
- **Makefile** with 10+ targets for common operations
- **Comprehensive documentation** for setup and troubleshooting

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   GitHub Codespaces                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Kind Kubernetes Cluster               │  │
│  │          (2 nodes: control-plane + worker)         │  │
│  │                                                      │  │
│  │  ┌──────────────┐  ┌──────────────┐ ┌──────────────┐│  │
│  │  │   argocd     │  │    mysql     │ │   airflow    ││  │
│  │  │  namespace   │  │  namespace   │ │  namespace   ││  │
│  │  │              │  │              │ │              ││  │
│  │  │ • Server     │  │ • StatefulSet│ │ • Webserver  ││  │
│  │  │ • Repo Server│  │ • PVC (10Gi) │ │ • Scheduler  ││  │
│  │  │ • Controller │  │ • Service    │ │ • Triggerer  ││  │
│  │  │ • Redis      │  │              │ │              ││  │
│  │  └──────────────┘  └──────────────┘ └──────────────┘│  │
│  │                                                      │  │
│  └──────────────────────────────────────────────────────┘  │
│  Port Forwarding:                                           │
│  • Argo CD:  localhost:8080 → HTTPS                        │
│  • Airflow:  localhost:8090 → HTTP (when ready)            │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow: GitOps Pattern

```
Git Repository (k8s/) 
    ↓
Argo CD (App-of-Apps Pattern)
    ↓
MySQL App ──→ MySQL StatefulSet + PVC + Service
    ↓
Airflow App ──→ Airflow Deployments + ConfigMaps + Secrets
```

---

## ✅ Prerequisites

- ✅ GitHub Codespaces (or any Linux environment with Docker)
- ✅ Docker daemon running
- ✅ `kubectl` CLI (will be installed if missing)
- ✅ `kind` CLI (will be installed if missing)
- ✅ At least 4GB RAM and 20GB storage available

**All tools are automatically installed by setup scripts.**

---

## 🚀 Quick Start

### 1. Clone or Navigate to Repository

```bash
cd /workspaces/Codespace_PLAY
```

### 2. Start the Complete Stack

```bash
# Using Make (recommended)
make dev-up

# OR using shell script
bash scripts/dev-up.sh
```

**What happens**:
- Creates `kind` cluster with 2 nodes
- Deploys Argo CD with all required components
- Creates MySQL namespace and deploys StatefulSet
- Creates Airflow namespace and deploys all components
- Initializes databases and services

**Expected duration**: 3-5 minutes

### 3. Check Status

```bash
make status
# or
kubectl get pods -A

# Check specific namespaces
kubectl get pods -n argocd
kubectl get pods -n mysql
kubectl get pods -n airflow
```

### 4. Set Up Port Forwarding

```bash
# Using Make
make port-forward-argocd    # Argo CD on port 8080
make port-forward-airflow   # Airflow on port 8090

# OR using individual scripts
bash scripts/argocd-port-forward.sh
bash scripts/airflow-port-forward.sh
```

**For Codespaces**: Port forwarding is automatic via "Ports" tab in VS Code

### 5. Access the Services

See [Accessing the Services](#accessing-the-services) section below.

---

## 🌐 Accessing the Services

### Via GitHub Codespaces (VS Code)

1. **Open in Simple Browser Tab** (recommended for this POC):
   ```bash
   # Argo CD
   code --command simpleBrowser.show https://localhost:8080
   
   # Airflow
   code --command simpleBrowser.show http://localhost:8090
   ```

2. **Via Ports Tab**: 
   - Click the "Ports" tab in VS Code terminal area
   - Right-click port 8080 (Argo CD) or 8090 (Airflow)
   - Select "Open in Browser" or "Copy Public URL"

3. **Via Direct URLs** (if port forwarding is active):
   - Argo CD: `https://localhost:8080`
   - Airflow: `http://localhost:8090` (when ready)

### Login Credentials

**Argo CD**:
- Username: `admin`
- Password: `9O1sUZU40W97yCHC`

**Airflow** (when ready):
- Username: `admin`
- Password: `airflowadmin`

---

## 📁 Project Structure

```
Codespace_PLAY/
├── README.md                          # This file
├── Makefile                           # Management targets
├── k8s/                               # Kubernetes manifests
│   ├── mysql/
│   │   ├── base/                      # MySQL base components
│   │   │   ├── statefulset.yaml       # StatefulSet + PVC
│   │   │   ├── service.yaml           # ClusterIP service
│   │   │   ├── configmap.yaml         # Database init script
│   │   │   └── kustomization.yaml
│   │   └── overlays/
│   │       └── dev/                   # Dev environment overlay
│   │           └── kustomization.yaml
│   ├── airflow/
│   │   ├── base/                      # Airflow base components
│   │   │   ├── webserver-deployment.yaml    # API server (3.0+)
│   │   │   ├── scheduler-deployment.yaml    # Scheduler
│   │   │   ├── triggerer-deployment.yaml    # Event triggerer
│   │   │   ├── migrate-job.yaml             # DB migration PreSync
│   │   │   ├── create-admin-job.yaml        # Admin creation PostSync
│   │   │   ├── serviceaccount.yaml          # RBAC for pod creation
│   │   │   ├── configmap.yaml               # Executor config
│   │   │   ├── secret.yaml                  # DB credentials
│   │   │   └── kustomization.yaml
│   │   └── overlays/
│   │       └── dev/                   # Dev environment overlay
│   │           └── kustomization.yaml
│   └── apps/                          # Argo CD applications
│       ├── app-of-apps.yaml           # Parent app (watches k8s/apps)
│       ├── mysql-app.yaml             # Child app for MySQL
│       └── airflow-app.yaml           # Child app for Airflow
├── scripts/                           # Automation scripts
│   ├── dev-up.sh                      # Start entire stack
│   ├── dev-down.sh                    # Tear down stack
│   ├── status.sh                      # Check component status
│   ├── argocd-port-forward.sh         # Argo CD port forwarding
│   └── airflow-port-forward.sh        # Airflow port forwarding
└── .credentials (gitignored)/
    ├── .argocd-password
    ├── .airflow-password
    └── .mysql-password
```

---

## ⚙️ Configuration Details

### Kubernetes Cluster (kind)

- **Name**: `gitops-poc`
- **Nodes**: 
  - 1 control-plane (runs workloads too)
  - 1 worker node
- **Kubernetes Version**: v1.35.0
- **Container Runtime**: containerd

### Namespaces

| Namespace | Components | Purpose |
|-----------|-----------|---------|
| `argocd` | Argo CD server, controller, repo-server, redis, etc. | GitOps automation |
| `mysql` | MySQL StatefulSet with PVC | Metadata database |
| `airflow` | Airflow webserver, scheduler, triggerer | Task orchestration |
| `kube-system` | DNS, proxy, ingress | System services |

### MySQL Configuration

- **Version**: 8.0
- **Storage**: 10Gi PVC (persistent)
- **Service**: `dev-mysql` (headless, ClusterIP: None)
- **Database**: `airflow`
- **User**: `airflow`
- **Connection String**: 
  ```
  mysql+pymysql://airflow:airflowpass@dev-mysql.mysql.svc.cluster.local:3306/airflow
  ```

### Airflow Configuration

- **Version**: Apache Airflow 3.0.1
- **Image**: `apache/airflow:3.0.1-python3.12`
- **Executor**: KubernetesExecutor (tasks run as pods)
- **Database**: MySQL (via secret `AIRFLOW__CORE__SQL_ALCHEMY_CONN`)
- **API Server**: `api-server` command (Airflow 3.0+ change)
- **Services**:
  - `dev-airflow-webserver`: Port 8080 (ClusterIP)
  - Internal scheduler and triggerer communication via DNS

### Argo CD Configuration

- **Version**: v3.3.2
- **Pattern**: App-of-Apps (root application watches `/k8s/apps`)
- **Sync Policy**: Automated with prune and self-heal enabled
- **Services**:
  - `argocd-server`: Port 80/443 (ClusterIP)
  - Internal service-to-service communication

### GitOps Integration

**How It Works**:
1. Argo CD **root app** (`app-of-apps.yaml`) watches the `k8s/apps/` directory
2. Root app detects **child apps** (`mysql-app.yaml`, `airflow-app.yaml`)
3. Each child app points to **Kustomize overlays**:
   - MySQL: `k8s/mysql/overlays/dev`
   - Airflow: `k8s/airflow/overlays/dev`
4. Kustomize **merges base configs** with **environment overlays**
5. Argo CD **automatically syncs** changes to the cluster

---

## 🔧 Common Tasks

### View All Pods Across Namespaces
```bash
kubectl get pods -A
```

### Check Specific Pod Status
```bash
# Argo CD pods
kubectl get pods -n argocd

# MySQL pods
kubectl get pods -n mysql

# Airflow pods
kubectl get pods -n airflow
```

### View Pod Logs
```bash
# Argo CD server
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f

# Airflow webserver
kubectl logs -n airflow -l app=airflow-webserver -f

# Airflow scheduler
kubectl logs -n airflow -l app=airflow-scheduler -f
```

### Describe a Pod (detailed info)
```bash
kubectl describe pod -n airflow dev-airflow-webserver-<pod-id>
```

### Access MySQL
```bash
# From inside cluster
kubectl run -it --rm mysql-client --image=mysql:8.0 -n mysql -- \
  mysql -h dev-mysql -u airflow -p airflow

# Or port-forward MySQL
kubectl port-forward -n mysql svc/dev-mysql 3306:3306
mysql -h 127.0.0.1 -u airflow -p airflow
```

### Restart a Deployment
```bash
# Airflow webserver
kubectl rollout restart deployment/dev-airflow-webserver -n airflow

# Airflow scheduler
kubectl rollout restart deployment/dev-airflow-scheduler -n airflow
```

### Scale a Deployment
```bash
# Scale Argo CD dex-server
kubectl scale deployment argocd-dex-server -n argocd --replicas=2
```

---

## 🐛 Troubleshooting

### Argo CD Server Not Responding

**Symptom**: Connection refused or timeout when accessing Argo CD

**Solution**:
```bash
# Verify port-forward is running
ps aux | grep "kubectl port-forward"

# Restart port-forward
pkill -f "kubectl port-forward"
kubectl port-forward -n argocd svc/argocd-server 8080:443 &

# Test connectivity
curl -k https://localhost:8080/
```

### Airflow Pods in CrashLoopBackOff

**Symptom**: Airflow webserver/scheduler/triggerer pods restarting repeatedly

**Check logs**:
```bash
kubectl logs -n airflow dev-airflow-webserver-<pod-id>
```

**Common causes**:
- ❌ Database migration failed: Check `dev-airflow-db-migrate-*` job logs
- ❌ MySQL not accessible: Verify MySQL pod is running and service is discoverable
- ❌ Secret not loaded: Verify `airflow-secret` exists in airflow namespace

**Solutions**:
```bash
# Check MySQL is running
kubectl get pods -n mysql

# Check secret exists
kubectl get secrets -n airflow

# View migration job logs
kubectl logs -n airflow -l job-name=dev-airflow-db-migrate

# View admin creation logs
kubectl logs -n airflow -l job-name=dev-airflow-create-admin
```

### MySQL Pod Stuck in Pending

**Symptom**: MySQL pod shows "Pending" status

**Cause**: PVC cannot be created or storage class missing

**Solution**:
```bash
# Check PVC status
kubectl get pvc -n mysql

# Check PVC events
kubectl describe pvc -n mysql dev-mysql-pvc

# Check storage classes
kubectl get storageclass
```

### Port Forwarding Not Working in Codespaces

**Symptom**: Browser shows "Connection refused" or "Can't reach server"

**Solution**:
1. **Check port-forward process**:
   ```bash
   ps aux | grep "kubectl port-forward"
   ```

2. **Restart port-forward**:
   ```bash
   pkill -f "kubectl port-forward"
   kubectl port-forward -n argocd svc/argocd-server 8080:443 &
   ```

3. **Test with curl**:
   ```bash
   curl -k https://localhost:8080/
   ```

4. **Check VS Code Ports tab**:
   - If port doesn't appear in Ports tab, manually start port-forward

### Git Init Errors

**If git history is missing**:
```bash
cd /workspaces/Codespace_PLAY
git log --oneline | head -10
```

---

## 📊 Monitoring and Observability

### Check Cluster Health
```bash
# Cluster info
kubectl cluster-info

# Node status
kubectl top nodes

# Pod resource usage
kubectl top pods -A
```

### View Events
```bash
# All events in all namespaces
kubectl get events -A --sort-by='.lastTimestamp'

# Events in specific namespace
kubectl get events -n airflow
```

### Check Service Endpoints
```bash
# MySQL endpoints
kubectl get endpoints -n mysql dev-mysql

# Argo CD service endpoints
kubectl get endpoints -n argocd argocd-server

# Airflow endpoints
kubectl get endpoints -n airflow dev-airflow-webserver
```

---

## 🛑 Shutdown and Cleanup

### Stop Everything (Keep Data)
```bash
make dev-down
# or
bash scripts/dev-down.sh
```

### Destroy Everything
```bash
# Delete entire kind cluster
kind delete cluster --name gitops-poc
```

---

## 📝 Git Commands

### View Commit History
```bash
git log --oneline
```

### View Changes
```bash
git status
git diff
```

### Add and Commit
```bash
git add .
git commit -m "Description of changes"
git push origin main
```

---

## 🎓 Learning Resources

### What's in This POC?

1. **Kubernetes**: Container orchestration, namespaces, deployments, StatefulSets, RBAC
2. **Argo CD**: GitOps, declarative infrastructure, app-of-apps pattern, automated sync
3. **MySQL**: Persistent storage (PVC), StatefulSets, database backends
4. **Apache Airflow**: Task orchestration, KubernetesExecutor, DAG scheduling
5. **GitOps Workflow**: Infrastructure as Code, version control-driven deployments
6. **Kustomize**: Configuration management, overlays for environments

### Quick References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Apache Airflow Documentation](https://airflow.apache.org/)
- [Kustomize Documentation](https://kustomize.io/)
- [kind Documentation](https://kind.sigs.k8s.io/)

---

## 📞 Next Steps

### Immediate Next Steps

1. **Access Argo CD**:
   - Open `https://localhost:8080`
   - Login with provided credentials
   - Explore the GitOps dashboard

2. **Monitor Airflow Initialization**:
   - Watch pod status: `kubectl get pods -n airflow -w`
   - Check logs: `kubectl logs -n airflow -l app=airflow`

3. **Verify Data Persistence**:
   - MySQL PVC: `kubectl get pvc -n mysql`
   - Database: Connect and verify tables created

### Advanced Tasks

1. **Add Custom DAGs**: Place DAG files in `dags/` volume
2. **Modify Configurations**: Update ConfigMaps and re-sync via Argo CD
3. **Scale Components**: Adjust replicas using `kubectl scale`
4. **Add Ingress**: Expose services via Ingress controller
5. **Add Secrets Management**: Integrate Sealed Secrets or External Secrets Operator

---

## 📊 Summary of Setup

| Aspect | Value |
|--------|-------|
| **Total Pods Running** | 15+ (7 Argo CD, 1 MySQL, 5+ Airflow, system pods) |
| **Storage Used** | 10Gi MySQL PVC + ephemeral volumes |
| **CPU/Memory** | Varies with load; typically <2GB RAM for POC |
| **Network Isolation** | 3 namespaces (argocd, mysql, airflow) |
| **Git Integration** | Kustomize overlays + Argo CD app-of-apps |
| **Port Forwarding** | Argo CD (8080), Airflow (8090), MySQL (3306) |
| **Setup Duration** | ~3-5 minutes after first `make dev-up` |
| **Tear Down Duration** | ~1 minute with `make dev-down` |

---

## 📄 License

This POC is provided as-is for learning and testing purposes.

---

## 🤝 Contributing

To improve this POC:

1. Make changes to YAML files in `k8s/`
2. Test with `make dev-up && make status`
3. Commit to git: `git add . && git commit -m "description"`
4. Push to repository: `git push origin main`

---

**Last Updated**: February 25, 2026  
**Status**: ✅ Fully Operational  
**All Components**: Running and accessible

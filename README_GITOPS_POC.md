# 📖 CI/CD + GitOps POC - Complete Setup Guide

Welcome! This is a complete, ready-to-use CI/CD + GitOps proof-of-concept with Kubernetes, Argo CD, MySQL, and Apache Airflow 3.0.

## 🚀 START HERE (30 seconds)

### Option A: Fast Setup
```bash
make dev-up
```

### Option B: Interactive Setup
```bash
./QUICKSTART.sh
```

**Time**: ~5-10 minutes  
**Result**: Full local Kubernetes cluster with all services running

---

## 📚 Documentation Index

Choose based on your needs:

| Document | Purpose | Read Time |
|----------|---------|-----------|
| **[SETUP.md](SETUP.md)** | 👈 **START HERE** - Quick start & basic commands | 5 min |
| **[SETUP_SUMMARY.md](SETUP_SUMMARY.md)** | What was built & architecture overview | 5 min |
| **[GITOPS_POC_README.md](GITOPS_POC_README.md)** | Deep dive - config, troubleshooting, advanced topics | 15 min |
| **[Makefile](Makefile)** | All management targets & commands | See `make help` |

---

## 🎯 Quick Command Reference

```bash
# Setup & teardown
make dev-up              # Start everything (run this first!)
make dev-down            # Stop and delete cluster

# Access services
make argocd-ui           # Open Argo CD dashboard
make airflow-ui          # Open Airflow dashboard

# Debugging
make status              # Show component health
make logs                # View recent logs
make validate            # Validate k8s manifests

# Help
make help                # Show all targets
```

---

## 🏗️ What You'll Get

```
✅ Kubernetes cluster (kind)
   └─ 1 control-plane + 1 worker node

✅ Argo CD (GitOps automation)
   └─ Watches this repo for changes, auto-syncs

✅ MySQL 8.0 (database)
   └─ StatefulSet with persistent storage

✅ Apache Airflow 3.0.1
   ├─ Webserver (UI)
   ├─ Scheduler (runs DAGs)
   ├─ Triggerer (required for Airflow 3.0)
   └─ KubernetesExecutor (distributed task pods)
```

---

## 📋 Setup Checklist

- [ ] Read this file (you're here! ✓)
- [ ] Check [SETUP.md](SETUP.md) for prerequisites
- [ ] Run `make dev-up`
- [ ] Run `make status` to verify
- [ ] Open `make argocd-ui` and `make airflow-ui`
- [ ] Read [SETUP_SUMMARY.md](SETUP_SUMMARY.md) for architecture
- [ ] Bookmark [GITOPS_POC_README.md](GITOPS_POC_README.md) for reference

---

## ⚡ First 5 Minutes

```bash
# 1. Start everything
make dev-up

# 2. Check status
make status

# 3. Open Argo CD
make argocd-ui

# 4. Open Airflow
make airflow-ui

# 5. You're done!
```

---

## 🔧 Credentials & Secrets

After `make dev-up`, credentials are saved locally:

```
.mysql-credentials.txt      ← MySQL passwords
.airflow-credentials.txt    ← Airflow secrets
```

**These are NOT committed to git** (protected by .gitignore)

To retrieve Argo CD admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## 🌐 Service URLs (after setup)

| Service | URL | How to Access |
|---------|-----|---------------|
| **Argo CD** | https://localhost:8080 | `make argocd-ui` |
| **Airflow** | http://localhost:8090 | `make airflow-ui` |
| **MySQL** | localhost:3306 | Internal only |

---

## 🔄 GitOps Workflow

After setup, the GitOps workflow is automatic:

1. **Edit manifests** in `k8s/mysql/` or `k8s/airflow/`
2. **Commit & push** to GitHub
3. **Argo CD detects changes** within ~3 minutes
4. **Cluster auto-syncs** → new resources deployed

Or manually sync:
```bash
argocd app sync mysql-app
argocd app sync airflow-app
```

---

## 📁 Project Structure

```
.
├── k8s/                              # Kubernetes manifests
│   ├── mysql/
│   │   ├── base/                     # Base MySQL resources
│   │   └── overlays/dev/             # Dev environment overlay
│   ├── airflow/
│   │   ├── base/                     # Base Airflow resources
│   │   └── overlays/dev/             # Dev environment overlay
│   └── apps/                         # Argo CD Applications
│
├── scripts/
│   ├── dev-up.sh                     # Bootstrap entire environment
│   ├── dev-down.sh                   # Teardown
│   ├── status.sh                     # Component status
│   ├── argocd-port-forward.sh        # Argo CD UI access
│   └── airflow-port-forward.sh       # Airflow UI access
│
├── Makefile                          # Management targets
├── SETUP.md                          # Quick start guide
├── SETUP_SUMMARY.md                  # What was built
├── GITOPS_POC_README.md              # Full reference
└── README.md                         # This file
```

---

## 🧪 Test It Out

### Create a Simple DAG

```bash
# Create dags directory
mkdir -p dags

# Create a simple DAG
cat > dags/hello_dag.py << 'EOF'
from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime

with DAG('hello_dag', start_date=datetime(2024, 1, 1)):
    BashOperator(task_id='hello', bash_command='echo Hello Airflow!')
EOF

# Commit & push
git add dags/hello_dag.py
git commit -m "Add hello DAG"
git push

# Wait ~3 min for sync, then check Airflow UI
make airflow-ui
```

---

## 🐛 Troubleshooting

**Services not ready?**
```bash
make status          # Check component health
make logs            # View recent logs
```

**Cluster already exists?**
```bash
make dev-down
make dev-up
```

**Tools not installed?**
```bash
make install-prereqs
```

**Full troubleshooting guide**: See [GITOPS_POC_README.md](GITOPS_POC_README.md)

---

## 📚 Learning Resources

- 📖 [Argo CD Docs](https://argo-cd.readthedocs.io/)
- 📖 [Airflow 3.0 Docs](https://airflow.apache.org/docs/apache-airflow/stable/)
- 📖 [Kubernetes Docs](https://kubernetes.io/docs/)
- 📖 [Kustomize Docs](https://kustomize.io/)
- 📖 [kind Docs](https://kind.sigs.k8s.io/)

---

## 💾 Cleanup

To completely remove everything:

```bash
make dev-down
```

This will:
- Delete the kind cluster
- Remove all running services
- Clean up credential files
- Free up disk space

---

## 🎓 Next Steps

### Immediate
1. ✅ Run `make dev-up`
2. ✅ Check `make status`
3. ✅ Explore Argo CD UI
4. ✅ Explore Airflow UI

### Next
1. Read [SETUP_SUMMARY.md](SETUP_SUMMARY.md) for architecture details
2. Modify a manifest and watch GitOps auto-sync
3. Deploy a test DAG
4. Review Airflow logs

### Advanced
1. Read [GITOPS_POC_README.md](GITOPS_POC_README.md) for all features
2. Add custom Python packages to Airflow image
3. Scale components (scheduler, webserver)
4. Deploy to a real Kubernetes cluster (update REPO_URL)

---

## ❓ FAQ

**Q: How long does setup take?**  
A: ~5-10 minutes depending on internet speed and system resources.

**Q: Can I use this in production?**  
A: This is a POC/demo setup. For production, see recommendations in [GITOPS_POC_README.md](GITOPS_POC_README.md).

**Q: What if I modify the cluster manually?**  
A: Argo CD will reconcile it back to the desired state from git. That's GitOps!

**Q: How do I add more DAGs?**  
A: Add `.py` files to `dags/` folder, commit & push. Airflow auto-discovers them.

**Q: Can I scale components?**  
A: Yes! Edit `k8s/airflow/overlays/dev/kustomization.yaml` and adjust replicas.

---

## 🆘 Getting Help

1. Check [SETUP.md](SETUP.md) for quick commands
2. Review [GITOPS_POC_README.md](GITOPS_POC_README.md) troubleshooting section
3. Run `make status` and `make logs`
4. Check Kubernetes events: `kubectl get events -A`

---

## 📝 Summary

You now have a **complete, production-inspired CI/CD + GitOps POC** with:

✅ **Infrastructure as Code**: All resources defined in git  
✅ **Automatic Sync**: Argo CD keeps cluster in sync with repo  
✅ **Distributed DAGs**: Airflow KubernetesExecutor runs tasks as pods  
✅ **Persistent Storage**: MySQL with PVC for data durability  
✅ **Security**: RBAC, secrets, health checks, logging  
✅ **Documentation**: Complete setup, troubleshooting, references  

---

## 🎉 Ready to Start?

```bash
make dev-up
```

**Questions?** See [SETUP.md](SETUP.md) or [GITOPS_POC_README.md](GITOPS_POC_README.md)

---

**Last Updated**: February 25, 2026  
**Status**: ✅ Complete and ready to use

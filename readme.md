# 🚀 Airflow 3.0 GitOps Platform

A production-grade, Kubernetes-native Airflow 3.0.0 environment managed via GitOps (Argo CD). This platform is fully host-independent, utilizing dynamic volume provisioning and distributed DAG synchronization.

## 🏗️ Architecture

- **Kubernetes (Kind)**: Multi-node cluster (`gitops-poc`).
- **Argo CD**: Implements the **App-of-Apps** pattern to bootstrap the entire stack.
- **Apache Airflow 3.0.0**: 
  - **Executor**: `KubernetesExecutor` (each task runs in its own pod).
  - **DAG Sync**: Independent `git-sync` sidecars and init-containers (No host mounts).
  - **Backend**: MySQL 8.0 (StatefulSet with Persistent Storage).
- **Storage Strategy**:
  - **Logs**: Dynamically provisioned RWO volumes.
  - **DAGs**: Ephemeral `emptyDir` synced from remote Git repository.

## 🛠️ Quick Start

### 1. Provision & Deploy
One command to create the Kind cluster, install Argo CD, and deploy Airflow/MySQL:
```bash
make dev-up
```
*Note: This script handles namespace creation, secrets generation, and application bootstrapping.*

### 2. Access Dashboards
Once the script completes, use the following endpoints:
- **Argo CD**: [https://localhost:8080](https://localhost:8080) (User: `admin`)
- **Airflow**: [http://localhost:8090](http://localhost:8090) (User: `admin`)
- **MySQL**: `127.0.0.1:3306`

*Credentials are automatically saved in `.argocd-credentials.txt` and `.airflow-credentials.txt`.*

## 📋 Common Commands

| `make argocd-ui` | Open Argo CD UI (auto port-forward) |
| `make airflow-ui` | Open Airflow UI (auto port-forward) |
| `make status` | Check the health of all pods and services |
| `make dev-down` | Tear down the entire cluster and clean up |
| `make logs` | Stream logs from the Airflow scheduler |
| `kubectl get pods -n airflow` | View active worker pods and deployments |

## 📦 Environment Details

- **Airflow Namespace**: `airflow`
- **Argo CD Namespace**: `argocd`
- **DB Namespace**: `mysql`
- **Version Tracking**: All manifests are synchronized from the `main` branch of this repository via Argo CD.

---
**Status**: ✅ Production-Ready Architecture | 🚀 Airflow 3.0.0 | ☸️ Kubernetes Native

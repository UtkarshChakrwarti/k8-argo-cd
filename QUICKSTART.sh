#!/bin/bash

# QUICK START SCRIPT
# Run this to set up the complete CI/CD + GitOps POC in ~5 minutes

set -euo pipefail

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         CI/CD + GitOps POC Quick Start                         ║"
echo "║    Kubernetes + Argo CD + MySQL + Airflow 3.0                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if already set up
if kind get clusters 2>/dev/null | grep -q "gitops-poc"; then
    echo "✓ Kind cluster 'gitops-poc' already exists!"
    echo ""
    echo "Next steps:"
    echo "  • View status:  make status"
    echo "  • Argo CD UI:   make argocd-ui"
    echo "  • Airflow UI:   make airflow-ui"
    echo "  • Logs:         make logs"
    echo "  • Stop:         make dev-down"
    exit 0
fi

echo "Step 1: Starting setup..."
echo ""

# Show what will be installed  
echo "This setup will:"
echo "  ✓ Create a kind cluster (1 control-plane + 1 worker)"
echo "  ✓ Install Argo CD for GitOps"
echo "  ✓ Install MySQL 8.0 as a StatefulSet"
echo "  ✓ Deploy Airflow 3.0.1 with KubernetesExecutor"
echo "  ✓ Enable automatic sync of changes from this repository"
echo ""

read -p "Ready to proceed? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 1
fi

echo ""
echo "Step 2: Checking prerequisites..."

# Check for required tools in dev-up.sh
make dev-up

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     ✓ SETUP COMPLETE!                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Access the services:"
echo ""
echo "  Argo CD       →  make argocd-ui        (https://localhost:8080)"
echo "  Airflow       →  make airflow-ui       (http://localhost:8090)"
echo "  All status    →  make status"
echo "  Show logs     →  make logs"
echo ""
echo "Clean up later:"
echo "  make dev-down"
echo ""
echo "For more info, see GITOPS_POC_README.md"
echo ""

#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLUSTER_NAME="gitops-poc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

main() {
    log_info "Tearing down GitOps POC environment..."

    # Kill kubectl port-forwards
    log_info "Stopping port-forwards..."
    pkill -f "kubectl port-forward" 2>/dev/null && log_success "Port-forwards stopped" || \
        log_warning "No kubectl port-forwards running"

    # Delete kind cluster (removes all nodes, pods, PVCs, namespaces)
    log_info "Deleting kind cluster: ${CLUSTER_NAME}"
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        kind delete cluster --name "$CLUSTER_NAME" || { log_error "Failed to delete cluster"; return 1; }
        log_success "Kind cluster deleted"
    else
        log_warning "Kind cluster '${CLUSTER_NAME}' not found"
    fi

    # Remove kubectl context leftover
    kubectl config delete-context "kind-${CLUSTER_NAME}" 2>/dev/null || true
    kubectl config delete-cluster "kind-${CLUSTER_NAME}" 2>/dev/null || true

    # Clean up temp/credential files
    log_info "Cleaning up credential and temp files..."
    rm -f "$SCRIPT_DIR/.mysql-credentials.txt" \
          "$SCRIPT_DIR/.airflow-credentials.txt" \
          "$SCRIPT_DIR/.argocd-credentials.txt" \
          /tmp/kind-config.yaml
    log_success "Cleanup complete"

    log_success "Environment fully torn down"
}

main "$@"

#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLUSTER_NAME="gitops-poc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GIT_DAEMON_PORT=9418

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

    # Stop git daemon
    log_info "Stopping git daemon..."
    local pid
    pid=$(pgrep -f "git daemon.*${GIT_DAEMON_PORT}" 2>/dev/null || true)
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null && log_success "Git daemon (PID ${pid}) stopped" || \
            log_warning "Could not stop git daemon"
    else
        log_warning "Git daemon not running"
    fi

    # Delete kind cluster
    log_info "Deleting kind cluster: ${CLUSTER_NAME}"
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        kind delete cluster --name "$CLUSTER_NAME" || { log_error "Failed to delete cluster"; return 1; }
        log_success "Kind cluster deleted"
    else
        log_warning "Kind cluster '${CLUSTER_NAME}' not found"
    fi

    # Clean up temp/credential files
    log_info "Cleaning up temp files..."
    rm -f "$SCRIPT_DIR/.mysql-credentials.txt" \
          "$SCRIPT_DIR/.airflow-credentials.txt" \
          /tmp/kind-config.yaml
    log_success "Cleanup complete"
}

main "$@"

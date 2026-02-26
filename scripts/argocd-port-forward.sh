#!/bin/bash

set -euo pipefail

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

ARGOCD_NAMESPACE="argocd"
ARGOCD_PORT="${ARGOCD_PORT:-8080}"

# Check if service exists
if ! kubectl get service argocd-server -n "$ARGOCD_NAMESPACE" &> /dev/null; then
    log_info "Argo CD server service not found in namespace '$ARGOCD_NAMESPACE'"
    exit 1
fi

log_success "Setting up port-forward to Argo CD server on port $ARGOCD_PORT..."
log_info "Access Argo CD at: https://localhost:$ARGOCD_PORT"
log_info "Press Ctrl+C to stop port-forward"

kubectl port-forward -n "$ARGOCD_NAMESPACE" svc/argocd-server "$ARGOCD_PORT:443"

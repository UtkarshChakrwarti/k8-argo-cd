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

MONITORING_NAMESPACE="monitoring"
MONITORING_SERVICE="kube-ops-view"
MONITORING_PORT="${MONITORING_PORT:-8091}"

if ! kubectl get service "$MONITORING_SERVICE" -n "$MONITORING_NAMESPACE" &> /dev/null; then
    log_info "Monitoring service '$MONITORING_SERVICE' not found in namespace '$MONITORING_NAMESPACE'"
    exit 1
fi

log_success "Setting up port-forward to monitoring UI on port $MONITORING_PORT..."
log_info "Access monitoring UI at: http://localhost:$MONITORING_PORT"
log_info "Press Ctrl+C to stop port-forward"

kubectl port-forward -n "$MONITORING_NAMESPACE" "svc/$MONITORING_SERVICE" "$MONITORING_PORT:80"

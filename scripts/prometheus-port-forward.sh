#!/bin/bash

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

NAMESPACE="airflow-core"
SERVICE_NAME="prometheus"
PORT="${PROMETHEUS_PORT:-9090}"

if ! kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" &> /dev/null; then
    log_info "Prometheus service '$SERVICE_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

log_success "Setting up port-forward to Prometheus on port $PORT..."
log_info "Access Prometheus at: http://localhost:$PORT"
log_info "Press Ctrl+C to stop port-forward"

kubectl port-forward -n "$NAMESPACE" "svc/$SERVICE_NAME" "$PORT:9090" --address 0.0.0.0

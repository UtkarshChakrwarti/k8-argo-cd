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
SERVICE_NAME="grafana"
PORT="${GRAFANA_PORT:-3000}"

if ! kubectl get service "$SERVICE_NAME" -n "$NAMESPACE" &> /dev/null; then
    log_info "Grafana service '$SERVICE_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

log_success "Setting up port-forward to Grafana on port $PORT..."
log_info "Access Grafana at: http://localhost:$PORT"
log_info "Default credentials: admin/admin"
log_info "Press Ctrl+C to stop port-forward"

kubectl port-forward -n "$NAMESPACE" "svc/$SERVICE_NAME" "$PORT:3000"

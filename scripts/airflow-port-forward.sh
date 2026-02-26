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

AIRFLOW_NAMESPACE="airflow"
AIRFLOW_PORT="${AIRFLOW_PORT:-8090}"

# Check if service exists
if ! kubectl get service dev-airflow-webserver -n "$AIRFLOW_NAMESPACE" &> /dev/null; then
    log_info "Airflow webserver service not found in namespace '$AIRFLOW_NAMESPACE'"
    exit 1
fi

log_success "Setting up port-forward to Airflow webserver on port $AIRFLOW_PORT..."
log_info "Access Airflow at: http://localhost:$AIRFLOW_PORT"
log_info "Press Ctrl+C to stop port-forward"

kubectl port-forward -n "$AIRFLOW_NAMESPACE" svc/dev-airflow-webserver "$AIRFLOW_PORT:8080"

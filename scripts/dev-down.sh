#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="gitops-poc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Main function
main() {
    log_info "Tearing down GitOps POC environment..."
    
    log_info "Deleting kind cluster: $CLUSTER_NAME"
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        kind delete cluster --name "$CLUSTER_NAME" || {
            log_error "Failed to delete kind cluster"
            return 1
        }
        log_success "Kind cluster deleted"
    else
        log_warning "Kind cluster '$CLUSTER_NAME' not found"
    fi
    
    log_info "Cleaning up temporary files..."
    rm -f "$SCRIPT_DIR/.mysql-credentials.txt"
    rm -f "$SCRIPT_DIR/.airflow-credentials.txt"
    rm -f /tmp/kind-config.yaml
    
    log_success "Cleanup completed successfully"
    exit 0
}

# Run main function
main "$@"

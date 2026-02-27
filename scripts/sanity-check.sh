#!/bin/bash

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

failures=0

check_required_files() {
    log_info "Checking required files..."
    local required=(
        "k8s/apps/app-of-apps.yaml"
        "k8s/apps/mysql-app.yaml"
        "k8s/apps/airflow-app.yaml"
        "k8s/apps/monitoring-app.yaml"
        "k8s/monitoring/overlays/dev/kustomization.yaml"
        "SOE_myntra_k8s_apps/k8s_config_files/pac-qacluster03/airflow/kustomization.yaml"
        "scripts/dev-up.sh"
        "scripts/dev-down.sh"
        "scripts/status.sh"
        "scripts/monitoring-port-forward.sh"
        "scripts/prometheus-port-forward.sh"
        "scripts/grafana-port-forward.sh"
        "docs/airflow-scaling-and-capacity.md"
        "dags/example_user_namespace.py"
        "dags/example_core_namespace.py"
        "dags/example_mixed_namespace.py"
    )

    local missing=()
    for f in "${required[@]}"; do
        if [ ! -f "$f" ]; then
            missing+=("$f")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_err "Missing required files: ${missing[*]}"
        failures=$((failures + 1))
    else
        log_ok "Required file set is complete"
    fi
}

validate_manifests() {
    log_info "Validating kustomize manifests..."
    local paths=(
        "k8s/mysql/overlays/dev"
        "k8s/airflow/overlays/dev"
        "k8s/monitoring/overlays/dev"
        "k8s/apps"
    )

    local path
    for path in "${paths[@]}"; do
        if kubectl kustomize "$path" >/dev/null; then
            log_ok "Valid: $path"
        else
            log_err "Invalid: $path"
            failures=$((failures + 1))
        fi
    done
}

check_legacy_references() {
    log_info "Checking for stale legacy references..."
    local pattern='namespace: airflow$|dev-airflow-webserver|AIRFLOW_NAMESPACE="airflow"|kubectl get pods -n airflow\\b'

    if rg -n "$pattern" README.md scripts k8s --glob '!scripts/sanity-check.sh' >/tmp/gitops-sanity-legacy.txt; then
        log_err "Legacy single-namespace references still exist:"
        cat /tmp/gitops-sanity-legacy.txt
        failures=$((failures + 1))
    else
        log_ok "No stale single-namespace references found"
    fi

    rm -f /tmp/gitops-sanity-legacy.txt
}

check_cluster_state() {
    if ! command -v kind >/dev/null 2>&1; then
        log_warn "kind CLI not installed; skipping live cluster checks"
        return
    fi

    if ! kind get clusters 2>/dev/null | rg -q '^gitops-poc$'; then
        log_warn "Kind cluster 'gitops-poc' not running; skipping live cluster checks"
        return
    fi

    log_info "Running live cluster checks..."
    if kubectl -n argocd get applications >/dev/null 2>&1; then
        kubectl -n argocd get applications
        log_ok "ArgoCD applications are reachable"
    else
        log_warn "ArgoCD applications not reachable"
    fi
}

main() {
    check_required_files
    validate_manifests
    check_legacy_references
    check_cluster_state

    if [ "$failures" -gt 0 ]; then
        log_err "Sanity check failed with ${failures} issue(s)"
        exit 1
    fi

    log_ok "Sanity check passed"
}

main "$@"

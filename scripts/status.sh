#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="gitops-poc"
ARGOCD_NAMESPACE="argocd"
MYSQL_NAMESPACE="mysql"
AIRFLOW_CORE_NAMESPACE="airflow-core"
AIRFLOW_USER_NAMESPACE="airflow-user"
MONITORING_NAMESPACE="airflow-core"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_section() {
    echo -e "${CYAN}========== $1 ==========${NC}"
}

check_status() {
    local label=$1
    local namespace=$2
    local resource_type=$3
    local resource_name=$4

    if kubectl get "$resource_type" -n "$namespace" "$resource_name" &> /dev/null; then
        if [ "$resource_type" = "deployment" ] || [ "$resource_type" = "statefulset" ]; then
            local desired
            local ready
            desired=$(kubectl get "$resource_type" -n "$namespace" "$resource_name" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
            ready=$(kubectl get "$resource_type" -n "$namespace" "$resource_name" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            desired=${desired:-0}
            ready=${ready:-0}

            if [ "$desired" -gt 0 ] && [ "$ready" = "$desired" ]; then
                echo -e "${GREEN}✓${NC} $label: Ready (${ready}/${desired})"
            elif [ "$ready" -gt 0 ]; then
                echo -e "${YELLOW}?${NC} $label: Partially Ready (${ready}/${desired})"
            else
                echo -e "${RED}✗${NC} $label: Not Ready (${ready}/${desired})"
            fi
            return
        fi

        local ready_cond
        ready_cond=$(kubectl get "$resource_type" -n "$namespace" "$resource_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$ready_cond" = "True" ]; then
            echo -e "${GREEN}✓${NC} $label: Ready"
        elif [ "$ready_cond" = "False" ]; then
            echo -e "${RED}✗${NC} $label: Not Ready"
        else
            echo -e "${YELLOW}?${NC} $label: Unknown"
        fi
    else
        echo -e "${RED}✗${NC} $label: Not Found"
    fi
}

# Main function
main() {
    # Check if cluster exists
    if ! kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        log_info "Kind cluster '$CLUSTER_NAME' is not running"
        exit 1
    fi

    log_info "Cluster: $CLUSTER_NAME (running)"
    echo ""

    # Argo CD status
    log_section "Argo CD (namespace: $ARGOCD_NAMESPACE)"
    check_status "Server" "$ARGOCD_NAMESPACE" "deployment" "argocd-server"
    check_status "Controller" "$ARGOCD_NAMESPACE" "statefulset" "argocd-application-controller"
    check_status "Repo Server" "$ARGOCD_NAMESPACE" "deployment" "argocd-repo-server"

    # Get application status
    log_info "Applications:"
    kubectl get applications -n "$ARGOCD_NAMESPACE" -o wide || echo "No applications found"
    echo ""

    # MySQL status
    log_section "MySQL (namespace: $MYSQL_NAMESPACE)"
    check_status "MySQL StatefulSet" "$MYSQL_NAMESPACE" "statefulset" "dev-mysql"

    # Show MySQL pod status
    log_info "MySQL Pods:"
    kubectl get pods -n "$MYSQL_NAMESPACE" -o wide || echo "No pods found"
    echo ""

    # Airflow Control Plane status
    log_section "Airflow Control Plane (namespace: $AIRFLOW_CORE_NAMESPACE)"
    check_status "Webserver" "$AIRFLOW_CORE_NAMESPACE" "deployment" "airflow-webserver"
    check_status "Scheduler" "$AIRFLOW_CORE_NAMESPACE" "deployment" "airflow-scheduler"
    check_status "Triggerer" "$AIRFLOW_CORE_NAMESPACE" "deployment" "airflow-triggerer"
    check_status "DAG Processor" "$AIRFLOW_CORE_NAMESPACE" "deployment" "airflow-dag-processor"
    check_status "DAG Sync" "$AIRFLOW_CORE_NAMESPACE" "deployment" "airflow-dag-sync"

    log_info "Airflow Core Pods:"
    kubectl get pods -n "$AIRFLOW_CORE_NAMESPACE" -o wide || echo "No pods found"
    echo ""

    # Airflow User namespace (task pods)
    log_section "Airflow Task Pods (namespace: $AIRFLOW_USER_NAMESPACE)"
    log_info "Task Pods:"
    kubectl get pods -n "$AIRFLOW_USER_NAMESPACE" -o wide 2>/dev/null || echo "No task pods running"
    echo ""

    # Monitoring status
    log_section "Monitoring Stack (namespace: $MONITORING_NAMESPACE)"
    check_status "Kube Ops View" "$MONITORING_NAMESPACE" "deployment" "kube-ops-view"
    check_status "Kube State Metrics" "$MONITORING_NAMESPACE" "deployment" "kube-state-metrics"
    check_status "Prometheus" "$MONITORING_NAMESPACE" "deployment" "prometheus"
    check_status "Grafana" "$MONITORING_NAMESPACE" "deployment" "grafana"
    log_info "Monitoring Pods:"
    kubectl get pods -n "$MONITORING_NAMESPACE" -o wide 2>/dev/null || echo "Monitoring deployment not ready yet"
    log_info "Monitoring Services:"
    kubectl get svc -n "$MONITORING_NAMESPACE" kube-ops-view kube-state-metrics prometheus grafana 2>/dev/null || true
    echo ""

    # Node status
    log_section "Cluster Nodes"
    kubectl get nodes -o wide || echo "No nodes found"
    echo ""

    # Ingress status
    log_section "Ingress (if configured)"
    kubectl get ingress -A || echo "No ingresses found"
}

main "$@"

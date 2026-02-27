#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLUSTER_NAME="gitops-poc"
ARGOCD_NAMESPACE="argocd"
MYSQL_NAMESPACE="mysql"
AIRFLOW_CORE_NAMESPACE="airflow-core"
AIRFLOW_USER_NAMESPACE="airflow-user"
MONITORING_NAMESPACE="airflow-core"
KIND_CONFIG="/tmp/kind-config.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="https://github.com/UtkarshChakrwarti/k8-argo-cd.git"
DAG_REPO_URL="https://github.com/UtkarshChakrwarti/remote_airflow.git"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
GIT_BIN="/opt/homebrew/bin/git"
if ! command -v "$GIT_BIN" &>/dev/null; then
    GIT_BIN="git"
fi
# Keep GitOps revision explicit to avoid coupling Argo sync to local repo branch name.
GIT_REVISION="${GIT_REVISION:-feature/multi-namespace-executor}"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# ─── Prerequisites ───────────────────────────────────────────────────────────
check_prerequisites() {
    log_info "Checking for required tools..."
    local missing_tools=()
    for tool in docker kubectl kind argocd; do
        command -v "$tool" &>/dev/null || missing_tools+=("$tool")
    done
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    docker info &>/dev/null || { log_error "Docker daemon is not running"; return 1; }
    log_success "All prerequisites met"
}

# ─── Verify GitHub repo is reachable ──────────────────────────────────────────
verify_repo_access() {
    log_info "Verifying access to ${REPO_URL} (GitOps repo)..."
    "$GIT_BIN" ls-remote "$REPO_URL" HEAD &>/dev/null || {
        log_error "Cannot reach ${REPO_URL} – check network or repo permissions"
        return 1
    }
    log_success "GitOps repo accessible: ${REPO_URL}"

    log_info "Verifying access to ${DAG_REPO_URL} (DAG repo)..."
    "$GIT_BIN" ls-remote "$DAG_REPO_URL" HEAD &>/dev/null || {
        log_error "Cannot reach ${DAG_REPO_URL} – check network or repo permissions"
        return 1
    }
    log_success "DAG repo accessible: ${DAG_REPO_URL}"
}

# ─── Kind cluster ─────────────────────────────────────────────────────────────
create_kind_cluster() {
    log_info "Creating kind cluster: $CLUSTER_NAME"
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warning "Kind cluster '${CLUSTER_NAME}' already exists, skipping"
        return 0
    fi
    cat > "$KIND_CONFIG" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  - role: control-plane
    labels:
      ingress-ready: "true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
  - role: worker
EOF
    kind create cluster --config "$KIND_CONFIG" || { log_error "Failed to create cluster"; return 1; }
    kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1
    log_success "Kind cluster created"

    # Pre-load container images to avoid slow in-cluster pulls
    log_info "Pre-loading container images into Kind (speeds up first deploy)..."
    local images=(
        "apache/airflow:3.0.0-python3.12"
        "registry.k8s.io/git-sync/git-sync:v4.2.3"
    )
    local tmptar="/tmp/kind-image-load.tar"
    for img in "${images[@]}"; do
        if docker image inspect "$img" &>/dev/null || docker pull "$img" 2>/dev/null; then
            docker save "$img" -o "$tmptar" 2>/dev/null && \
                kind load image-archive "$tmptar" --name "$CLUSTER_NAME" 2>/dev/null && \
                log_success "  ${img##*/} loaded" || \
                log_warning "  ${img##*/} — kind load failed, nodes will pull it"
            rm -f "$tmptar"
        else
            log_warning "  ${img##*/} — pull failed, nodes will pull it directly"
        fi
    done
}

# ─── Node Pools / Taints ─────────────────────────────────────────────────────
configure_node_pools() {
    log_info "Configuring node pools for Airflow (core/user)..."

    workers=()
    while IFS= read -r node; do
        workers+=("$node")
    done < <(kubectl get nodes -o name | sed 's|node/||' | rg 'worker' | sort)

    if [ "${#workers[@]}" -eq 0 ]; then
        log_error "No worker nodes found to label/taint"
        return 1
    fi

    local core_node="${workers[0]}"
    kubectl label node "$core_node" airflow-node-pool=core --overwrite >/dev/null
    kubectl taint node "$core_node" dedicated- >/dev/null 2>&1 || true

    if [ "${#workers[@]}" -ge 2 ]; then
        local user_node="${workers[1]}"
        kubectl label node "$user_node" airflow-node-pool=user --overwrite >/dev/null
        kubectl taint node "$user_node" dedicated=airflow-user:NoSchedule --overwrite >/dev/null
        log_success "Node pool configured: core=${core_node}, user=${user_node} (tainted dedicated=airflow-user:NoSchedule)"
    else
        log_warning "Only one worker node found (${core_node}); user-task isolation taint could not be configured"
    fi
}


# ─── Ingress NGINX ────────────────────────────────────────────────────────────
install_ingress_nginx() {
    if kubectl get ns ingress-nginx &>/dev/null; then
        log_warning "ingress-nginx already installed, skipping"
        return 0
    fi
    log_info "Installing ingress-nginx..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml || {
        log_error "Failed to install ingress-nginx"; return 1
    }
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s 2>/dev/null || log_warning "Timeout on ingress-nginx, continuing..."
    log_success "ingress-nginx installed"
}

# ─── Argo CD ─────────────────────────────────────────────────────────────────
install_argocd() {
    if kubectl get ns "$ARGOCD_NAMESPACE" &>/dev/null && \
       kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        log_warning "Argo CD already installed, skipping"
        return 0
    fi
    log_info "Installing Argo CD..."
    kubectl create namespace "$ARGOCD_NAMESPACE" 2>/dev/null || true
    kubectl apply -n "$ARGOCD_NAMESPACE" \
        --server-side --force-conflicts \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || {
        log_error "Failed to install Argo CD"; return 1
    }
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server -n "$ARGOCD_NAMESPACE" 2>/dev/null || \
        log_warning "Timeout on Argo CD server, continuing..."

    log_info "Setting Argo CD admin password to 'admin'..."
    kubectl patch secret argocd-secret -n "$ARGOCD_NAMESPACE" \
        -p '{"stringData": {"admin.password": "$2b$12$oLr8O3sm54Tg00GUsSMhaOI5ipi2.Wb9wIihPERpczpQFb4oOa3MG", "admin.passwordMtime": "'$(date +%FT%T%Z)'"}}' || true

    log_success "Argo CD installed"
}

# ─── Namespaces ───────────────────────────────────────────────────────────────
create_namespaces() {
    log_info "Creating namespaces..."
    for ns in "$MYSQL_NAMESPACE" "$AIRFLOW_CORE_NAMESPACE" "$AIRFLOW_USER_NAMESPACE"; do
        kubectl get namespace "$ns" &>/dev/null || kubectl create namespace "$ns"
    done
    log_success "Namespaces ready: $MYSQL_NAMESPACE, $AIRFLOW_CORE_NAMESPACE, $AIRFLOW_USER_NAMESPACE"
}

# ─── MySQL secret ─────────────────────────────────────────────────────────────
create_mysql_secret() {
    log_info "Creating MySQL secrets..."
    if kubectl get secret mysql-secret -n "$MYSQL_NAMESPACE" &>/dev/null; then
        log_warning "MySQL secret already exists, skipping"
        AIRFLOW_DB_PASSWORD=$(kubectl get secret mysql-secret -n "$MYSQL_NAMESPACE" \
            -o jsonpath='{.data.airflow-password}' | base64 -d)
        return 0
    fi
    # Use hex passwords - URL-safe, no special chars
    MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(openssl rand -hex 20)}"
    AIRFLOW_DB_PASSWORD="${AIRFLOW_DB_PASSWORD:-$(openssl rand -hex 20)}"

    kubectl create secret generic mysql-secret \
        --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
        --from-literal=airflow-password="$AIRFLOW_DB_PASSWORD" \
        -n "$MYSQL_NAMESPACE" || { log_error "Failed to create MySQL secret"; return 1; }

    cat > "$SCRIPT_DIR/.mysql-credentials.txt" <<EOF
# MySQL Credentials (DO NOT COMMIT)
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
AIRFLOW_DB_PASSWORD=$AIRFLOW_DB_PASSWORD

===============================================
CONNECTION DETAILS FOR SQL GUI (DataGrip, DBeaver)
===============================================
Host: 127.0.0.1
Port: 3306

-- Root User (admin)
User: root
Password: $MYSQL_ROOT_PASSWORD
Database: (leave blank)

-- Airflow User
User: airflow
Password: $AIRFLOW_DB_PASSWORD
Database: airflow
EOF
    chmod 600 "$SCRIPT_DIR/.mysql-credentials.txt"
    log_warning "MySQL credentials saved to .mysql-credentials.txt"
    log_success "MySQL secret created"
}

# ─── Airflow secret (in BOTH namespaces) ─────────────────────────────────────
create_airflow_secret() {
    log_info "Creating Airflow secrets in both namespaces..."
    if kubectl get secret airflow-secret -n "$AIRFLOW_CORE_NAMESPACE" &>/dev/null; then
        log_warning "Airflow secret already exists in $AIRFLOW_CORE_NAMESPACE, skipping"
        return 0
    fi
    AIRFLOW_FERNET_KEY="${AIRFLOW_FERNET_KEY:-$(python3 -c \
        'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')}"
    AIRFLOW_WEBSERVER_SECRET_KEY="${AIRFLOW_WEBSERVER_SECRET_KEY:-$(openssl rand -hex 32)}"
    AIRFLOW_API_JWT_SECRET="${AIRFLOW_API_JWT_SECRET:-$(openssl rand -base64 32)}"
    AIRFLOW_ADMIN_PASSWORD="admin"

    # MySQL service is "dev-mysql" after kustomize namePrefix in mysql overlay
    SQL_ALCHEMY_CONN="mysql+pymysql://airflow:${AIRFLOW_DB_PASSWORD}@dev-mysql.mysql.svc.cluster.local:3306/airflow"

    # Create full secret in airflow-core namespace
    kubectl create secret generic airflow-secret \
        --from-literal=AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="$SQL_ALCHEMY_CONN" \
        --from-literal=AIRFLOW__CORE__FERNET_KEY="$AIRFLOW_FERNET_KEY" \
        --from-literal=AIRFLOW__WEBSERVER__SECRET_KEY="$AIRFLOW_WEBSERVER_SECRET_KEY" \
        --from-literal=AIRFLOW__API_AUTH__JWT_SECRET="$AIRFLOW_API_JWT_SECRET" \
        --from-literal=admin-password="$AIRFLOW_ADMIN_PASSWORD" \
        -n "$AIRFLOW_CORE_NAMESPACE" || { log_error "Failed to create Airflow secret in $AIRFLOW_CORE_NAMESPACE"; return 1; }
    log_success "Airflow secret created in $AIRFLOW_CORE_NAMESPACE"

    # Create secret in airflow-user namespace (task pods need DB conn)
    kubectl create secret generic airflow-secret \
        --from-literal=AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="$SQL_ALCHEMY_CONN" \
        --from-literal=AIRFLOW__CORE__FERNET_KEY="$AIRFLOW_FERNET_KEY" \
        -n "$AIRFLOW_USER_NAMESPACE" || { log_error "Failed to create Airflow secret in $AIRFLOW_USER_NAMESPACE"; return 1; }
    log_success "Airflow secret created in $AIRFLOW_USER_NAMESPACE"

    cat > "$SCRIPT_DIR/.airflow-credentials.txt" <<EOF
# Airflow Credentials (DO NOT COMMIT)
AIRFLOW_FERNET_KEY=$AIRFLOW_FERNET_KEY
AIRFLOW_WEBSERVER_SECRET_KEY=$AIRFLOW_WEBSERVER_SECRET_KEY
AIRFLOW_ADMIN_PASSWORD=$AIRFLOW_ADMIN_PASSWORD
SQL_ALCHEMY_CONN=$SQL_ALCHEMY_CONN
Airflow UI:   http://localhost:8090
  username:   admin
  password:   $AIRFLOW_ADMIN_PASSWORD
Namespaces:
  Control plane: $AIRFLOW_CORE_NAMESPACE
  Task pods:     $AIRFLOW_USER_NAMESPACE (default), $AIRFLOW_CORE_NAMESPACE (via executor_config)
EOF
    chmod 600 "$SCRIPT_DIR/.airflow-credentials.txt"
    log_warning "Airflow credentials saved to .airflow-credentials.txt"
}

# ─── Bootstrap Argo CD root app ───────────────────────────────────────────────
bootstrap_argocd() {
    log_info "Bootstrapping Argo CD root app (REPO_URL=${REPO_URL}, REV=${GIT_REVISION})..."
    local temp_app
    temp_app=$(mktemp)
    sed "s|\${REPO_URL}|${REPO_URL}|g" "$SCRIPT_DIR/k8s/apps/app-of-apps.yaml" > "$temp_app"

    if kubectl get application root-app -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        kubectl patch application root-app -n "$ARGOCD_NAMESPACE" \
            --type merge \
            -p "{\"spec\":{\"source\":{\"repoURL\":\"${REPO_URL}\",\"targetRevision\":\"${GIT_REVISION}\"}}}" || {
            rm "$temp_app"; log_error "Failed to patch root-app"; return 1
        }
    else
        kubectl create -n "$ARGOCD_NAMESPACE" -f "$temp_app" || {
            rm "$temp_app"; log_error "Failed to create root-app"; return 1
        }
    fi
    rm "$temp_app"
    log_success "Argo CD root app bootstrapped"
}

# ─── Patch / create child apps ────────────────────────────────────────────────
patch_child_apps() {
    log_info "Creating/patching child Argo CD apps (REV=${GIT_REVISION})..."
    for app in mysql-app airflow-app monitoring-app; do
        local temp_app
        temp_app=$(mktemp)
        sed "s|\${REPO_URL}|${REPO_URL}|g" "$SCRIPT_DIR/k8s/apps/${app}.yaml" > "$temp_app"

        if kubectl get application "$app" -n "$ARGOCD_NAMESPACE" &>/dev/null; then
            kubectl patch application "$app" -n "$ARGOCD_NAMESPACE" \
                --type merge \
                -p "{\"spec\":{\"source\":{\"repoURL\":\"${REPO_URL}\",\"targetRevision\":\"${GIT_REVISION}\"}}}" || {
                rm "$temp_app"; log_error "Failed to patch ${app}"; return 1
            }
        else
            kubectl create -n "$ARGOCD_NAMESPACE" -f "$temp_app" || {
                rm "$temp_app"; log_error "Failed to create ${app}"; return 1
            }
        fi
        rm "$temp_app"
        log_success "  ${app} ready"
    done
}

# ─── Wait for monitoring UI ───────────────────────────────────────────────────
wait_for_monitoring() {
    log_info "Waiting for monitoring deployments..."
    local deployments=(
        "kube-state-metrics"
        "prometheus"
        "grafana"
    )
    local deadline=$((SECONDS + 120))
    while true; do
        local all_exist=true
        for dep in "${deployments[@]}"; do
            if ! kubectl get deployment "$dep" -n "$MONITORING_NAMESPACE" &>/dev/null; then
                all_exist=false
                break
            fi
        done
        if $all_exist; then
            break
        fi
        if [ $SECONDS -ge $deadline ]; then
            log_warning "Timeout waiting for monitoring deployments creation"
            log_warning "Check ArgoCD sync status: argocd app get monitoring-app"
            return 1
        fi
        sleep 5
    done

    if kubectl wait --for=condition=available --timeout=240s \
        deployment/kube-state-metrics \
        deployment/prometheus \
        deployment/grafana \
        -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
        log_success "Monitoring stack is ready"
    else
        log_warning "Monitoring stack is not fully ready yet"
    fi
}

# ─── Wait for Airflow to be healthy ──────────────────────────────────────────
wait_for_airflow() {
    local deployments=(
        "airflow-dag-sync"
        "airflow-dag-processor"
        "airflow-scheduler"
        "airflow-webserver"
        "airflow-triggerer"
    )

    # Phase 1: Wait for ArgoCD to create the deployments (up to 120s)
    log_info "Waiting for ArgoCD to sync Airflow deployments..."
    local deadline=$((SECONDS + 120))
    while true; do
        local all_exist=true
        for dep in "${deployments[@]}"; do
            if ! kubectl get deployment "$dep" -n "$AIRFLOW_CORE_NAMESPACE" &>/dev/null; then
                all_exist=false
                break
            fi
        done
        if $all_exist; then
            log_success "All Airflow deployments created by ArgoCD"
            break
        fi
        if [ $SECONDS -ge $deadline ]; then
            log_warning "Timeout waiting for ArgoCD to create deployments"
            log_warning "Check ArgoCD sync status: argocd app get airflow-app"
            return 1
        fi
        sleep 5
    done

    # Phase 2: Wait for all deployments to become available
    log_info "Waiting for Airflow pods to be ready (may take 3-5 min)..."
    if kubectl wait --for=condition=available --timeout=300s \
        deployment/airflow-dag-sync \
        deployment/airflow-dag-processor \
        deployment/airflow-scheduler \
        deployment/airflow-webserver \
        deployment/airflow-triggerer \
        -n "$AIRFLOW_CORE_NAMESPACE" 2>&1 | while read -r line; do
            echo "  ${line}"
        done; then
        log_success "All Airflow components are ready"
    else
        log_warning "Some deployments not ready — check: kubectl get pods -n $AIRFLOW_CORE_NAMESPACE"
    fi
}

# ─── Ensure demo DAGs are active and visible ─────────────────────────────────
bootstrap_demo_dags() {
    local dags=(
        "example_user_namespace"
        "example_core_namespace"
        "example_mixed_namespace"
    )
    local scheduler_ref="deploy/airflow-scheduler"
    local ts
    ts="$(date +%s)"

    log_info "Unpausing and bootstrapping demo DAG runs..."
    for dag in "${dags[@]}"; do
        if kubectl -n "$AIRFLOW_CORE_NAMESPACE" exec "$scheduler_ref" -- airflow dags unpause "$dag" >/dev/null 2>&1; then
            log_success "  unpaused: ${dag}"
        else
            log_warning "  could not unpause: ${dag}"
            continue
        fi

        if kubectl -n "$AIRFLOW_CORE_NAMESPACE" exec "$scheduler_ref" -- airflow dags trigger "$dag" -r "bootstrap_${dag}_${ts}" >/dev/null 2>&1; then
            log_success "  triggered: ${dag}"
        else
            log_warning "  could not trigger: ${dag}"
        fi
    done
}

# ─── Port-forward Airflow UI ──────────────────────────────────────────────────
setup_airflow_portforward() {
    # Kill any stale port-forward
    pkill -f "kubectl port-forward.*airflow.*8090" 2>/dev/null || true
    sleep 1
    log_info "Starting Airflow port-forward on localhost:8090..."
    kubectl port-forward -n "$AIRFLOW_CORE_NAMESPACE" svc/airflow-webserver 8090:8080 \
        --address 0.0.0.0 >/dev/null 2>&1 &
    log_success "Airflow UI available at http://localhost:8090"
}

# ─── Port-forward Argo CD ─────────────────────────────────────────────────────
setup_argocd_portforward() {
    # Kill any stale port-forward for argocd
    pkill -f "kubectl port-forward.*argocd-server.*8080" 2>/dev/null || true
    sleep 1
    log_info "Starting Argo CD port-forward on localhost:8080..."
    kubectl port-forward -n "$ARGOCD_NAMESPACE" svc/argocd-server 8080:443 \
        --address 0.0.0.0 >/dev/null 2>&1 &
    log_success "Argo CD UI available at https://localhost:8080"

    cat > "$SCRIPT_DIR/.argocd-credentials.txt" <<EOF
# Argo CD Credentials (DO NOT COMMIT)

===============================================
CONNECTION DETAILS FOR ARGO CD
===============================================
UI URL: https://localhost:8080
Username: admin
Password: admin
EOF
    chmod 600 "$SCRIPT_DIR/.argocd-credentials.txt"
}

# ─── Port-forward MySQL ───────────────────────────────────────────────────────
setup_mysql_portforward() {
    # Kill any stale port-forward for mysql
    pkill -f "kubectl port-forward.*mysql.*3306" 2>/dev/null || true
    sleep 1
    log_info "Starting MySQL port-forward on localhost:3306..."
    kubectl port-forward -n "$MYSQL_NAMESPACE" svc/dev-mysql 3306:3306 \
        --address 0.0.0.0 >/dev/null 2>&1 &
    log_success "MySQL DB accessible at 127.0.0.1:3306"
}

# ─── Port-forward Prometheus ─────────────────────────────────────────────────
setup_prometheus_portforward() {
    pkill -f "kubectl port-forward.*prometheus.*${PROMETHEUS_PORT}" 2>/dev/null || true
    sleep 1
    log_info "Starting Prometheus port-forward on localhost:${PROMETHEUS_PORT}..."
    kubectl port-forward -n "$MONITORING_NAMESPACE" svc/prometheus "${PROMETHEUS_PORT}:9090" \
        --address 0.0.0.0 >/dev/null 2>&1 &
    log_success "Prometheus available at http://localhost:${PROMETHEUS_PORT}"
}

# ─── Port-forward Grafana ────────────────────────────────────────────────────
setup_grafana_portforward() {
    pkill -f "kubectl port-forward.*grafana.*${GRAFANA_PORT}" 2>/dev/null || true
    sleep 1
    log_info "Starting Grafana port-forward on localhost:${GRAFANA_PORT}..."
    kubectl port-forward -n "$MONITORING_NAMESPACE" svc/grafana "${GRAFANA_PORT}:3000" \
        --address 0.0.0.0 >/dev/null 2>&1 &
    log_success "Grafana available at http://localhost:${GRAFANA_PORT} (admin/admin)"
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    log_success "══════════════════════════════════════════"
    log_success " GitOps POC - Multi-Namespace Airflow Ready!"
    log_success "══════════════════════════════════════════"
    echo ""
    echo "  Argo CD UI   →  https://localhost:8080  (see .argocd-credentials.txt)"
    echo "  Airflow UI   →  http://localhost:8090   (see .airflow-credentials.txt)"
    echo "  MySQL DB     →  127.0.0.1:3306          (see .mysql-credentials.txt)"
    echo "  Prometheus   →  http://localhost:${PROMETHEUS_PORT}"
    echo "  Grafana      →  http://localhost:${GRAFANA_PORT} (admin/admin)"
    echo "  GitOps repo  →  ${REPO_URL}"
    echo "  DAG repo     →  ${DAG_REPO_URL}"
    echo ""
    echo "  Namespaces:"
    echo "    airflow-core  →  scheduler, webserver, triggerer, dag-processor, git-sync"
    echo "    airflow-user  →  task pods (default KubernetesExecutor target)"
    echo "  Demo DAG schedules:"
    echo "    example_user_namespace  → manual trigger"
    echo "    example_core_namespace  → manual trigger"
    echo "    example_mixed_namespace → manual trigger"
    echo ""
    echo "  make status      – component health"
    echo "  make logs        – tail logs"
    echo "  make dev-down    – tear everything down"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    log_info "Starting local GitOps POC (multi-namespace Airflow)..."
    check_prerequisites     || exit 1
    verify_repo_access      || exit 1
    create_kind_cluster     || exit 1
    configure_node_pools    || exit 1
    install_ingress_nginx   || exit 1
    install_argocd          || exit 1
    create_namespaces       || exit 1
    create_mysql_secret     || exit 1
    create_airflow_secret   || exit 1
    bootstrap_argocd        || exit 1
    patch_child_apps        || exit 1
    wait_for_airflow        || true
    bootstrap_demo_dags     || true
    wait_for_monitoring     || true
    setup_argocd_portforward  || true
    setup_airflow_portforward || true
    setup_mysql_portforward   || true
    setup_prometheus_portforward || true
    setup_grafana_portforward || true
    print_summary
}

main "$@"

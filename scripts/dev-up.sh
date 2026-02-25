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
AIRFLOW_NAMESPACE="airflow"
KIND_CONFIG="/tmp/kind-config.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="https://github.com/UtkarshChakrwarti/k8-argo-cd.git"

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
    log_info "Verifying access to ${REPO_URL}..."
    git ls-remote "$REPO_URL" HEAD &>/dev/null || {
        log_error "Cannot reach ${REPO_URL} – check network or repo permissions"
        return 1
    }
    log_success "Repo accessible: ${REPO_URL}"
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
      - containerPort: 8080
        hostPort: 8080
        protocol: TCP
      - containerPort: 8090
        hostPort: 8090
        protocol: TCP
    extraMounts:
      - hostPath: ${SCRIPT_DIR}/dags
        containerPath: /dags-host
  - role: worker
    extraMounts:
      - hostPath: ${SCRIPT_DIR}/dags
        containerPath: /dags-host
EOF
    kind create cluster --config "$KIND_CONFIG" || { log_error "Failed to create cluster"; return 1; }
    kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1
    log_success "Kind cluster created"
}

# ─── Build & load dag-sync image ─────────────────────────────────────────────
build_dag_sync() {
    log_info "Building dag-sync sidecar image..."
    docker build -t dag-sync:local "$SCRIPT_DIR/dag-sync/" || { log_error "Failed to build dag-sync"; return 1; }
    log_info "Loading dag-sync image into Kind..."
    kind load docker-image dag-sync:local --name "$CLUSTER_NAME" || { log_error "Failed to load dag-sync"; return 1; }
    log_success "dag-sync image ready"
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
    log_success "Argo CD installed"
}

# ─── Namespaces ───────────────────────────────────────────────────────────────
create_namespaces() {
    log_info "Creating namespaces..."
    for ns in "$MYSQL_NAMESPACE" "$AIRFLOW_NAMESPACE"; do
        kubectl get namespace "$ns" &>/dev/null || kubectl create namespace "$ns"
    done
    log_success "Namespaces ready"
}

# ─── MySQL secret ─────────────────────────────────────────────────────────────
create_mysql_secret() {
    log_info "Creating MySQL secrets..."
    # Kustomize overlay adds "dev-" prefix to all resource names, so secrets
    # created here must match the prefixed names that pods will reference.
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

# ─── Airflow secret ───────────────────────────────────────────────────────────
create_airflow_secret() {
    log_info "Creating Airflow secrets..."
    if kubectl get secret airflow-secret -n "$AIRFLOW_NAMESPACE" &>/dev/null; then
        log_warning "Airflow secret already exists, skipping"
        return 0
    fi
    AIRFLOW_FERNET_KEY="${AIRFLOW_FERNET_KEY:-$(python3 -c \
        'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')}"
    AIRFLOW_WEBSERVER_SECRET_KEY="${AIRFLOW_WEBSERVER_SECRET_KEY:-$(openssl rand -hex 32)}"
    AIRFLOW_ADMIN_PASSWORD="${AIRFLOW_ADMIN_PASSWORD:-$(openssl rand -hex 16)}"

    # Airflow 3.0: correct key is AIRFLOW__DATABASE__SQL_ALCHEMY_CONN
    # MySQL service is "dev-mysql" after kustomize namePrefix
    SQL_ALCHEMY_CONN="mysql+pymysql://airflow:${AIRFLOW_DB_PASSWORD}@dev-mysql.mysql.svc.cluster.local:3306/airflow"

    kubectl create secret generic airflow-secret \
        --from-literal=AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="$SQL_ALCHEMY_CONN" \
        --from-literal=AIRFLOW__CORE__FERNET_KEY="$AIRFLOW_FERNET_KEY" \
        --from-literal=AIRFLOW__WEBSERVER__SECRET_KEY="$AIRFLOW_WEBSERVER_SECRET_KEY" \
        --from-literal=admin-password="$AIRFLOW_ADMIN_PASSWORD" \
        -n "$AIRFLOW_NAMESPACE" || { log_error "Failed to create Airflow secret"; return 1; }

    cat > "$SCRIPT_DIR/.airflow-credentials.txt" <<EOF
# Airflow Credentials (DO NOT COMMIT)
AIRFLOW_FERNET_KEY=$AIRFLOW_FERNET_KEY
AIRFLOW_WEBSERVER_SECRET_KEY=$AIRFLOW_WEBSERVER_SECRET_KEY
AIRFLOW_ADMIN_PASSWORD=$AIRFLOW_ADMIN_PASSWORD
SQL_ALCHEMY_CONN=$SQL_ALCHEMY_CONN
Airflow UI:   http://localhost:8090
  username:   admin
  password:   $AIRFLOW_ADMIN_PASSWORD
EOF
    chmod 600 "$SCRIPT_DIR/.airflow-credentials.txt"
    log_warning "Airflow credentials saved to .airflow-credentials.txt"
    log_success "Airflow secret created"
}

# ─── Bootstrap Argo CD root app ───────────────────────────────────────────────
bootstrap_argocd() {
    log_info "Bootstrapping Argo CD root app (REPO_URL=${REPO_URL})..."
    local temp_app
    temp_app=$(mktemp)
    sed "s|\${REPO_URL}|${REPO_URL}|g" "$SCRIPT_DIR/k8s/apps/app-of-apps.yaml" > "$temp_app"

    if kubectl get application root-app -n "$ARGOCD_NAMESPACE" &>/dev/null; then
        kubectl patch application root-app -n "$ARGOCD_NAMESPACE" \
            --type merge \
            -p "{\"spec\":{\"source\":{\"repoURL\":\"${REPO_URL}\"}}}" || {
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
    log_info "Creating/patching child Argo CD apps..."
    for app in mysql-app airflow-app; do
        local temp_app
        temp_app=$(mktemp)
        sed "s|\${REPO_URL}|${REPO_URL}|g" "$SCRIPT_DIR/k8s/apps/${app}.yaml" > "$temp_app"

        if kubectl get application "$app" -n "$ARGOCD_NAMESPACE" &>/dev/null; then
            kubectl patch application "$app" -n "$ARGOCD_NAMESPACE" \
                --type merge \
                -p "{\"spec\":{\"source\":{\"repoURL\":\"${REPO_URL}\"}}}" || {
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

# ─── Wait for Airflow to be healthy ──────────────────────────────────────────
wait_for_airflow() {
    log_info "Waiting for Airflow webserver (may take 3-5 min)..."
    for i in $(seq 1 180); do
        if kubectl wait --for=condition=available --timeout=5s \
            deployment/dev-airflow-webserver -n "$AIRFLOW_NAMESPACE" &>/dev/null; then
            log_success "Airflow webserver is ready"
            return 0
        fi
        [ $((i % 10)) -eq 0 ] && echo -n " ${i}s" || echo -n "."
        sleep 1
    done
    echo ""
    log_warning "Airflow webserver not ready within timeout - check: kubectl get pods -n airflow"
}

# ─── Port-forward Airflow UI ──────────────────────────────────────────────────
setup_airflow_portforward() {
    # Kill any stale port-forward
    pkill -f "kubectl port-forward.*airflow.*8090" 2>/dev/null || true
    sleep 1
    log_info "Starting Airflow port-forward on localhost:8090..."
    kubectl port-forward -n "$AIRFLOW_NAMESPACE" svc/dev-airflow-webserver 8090:8080 \
        --address 0.0.0.0 >/dev/null 2>&1 &
    log_success "Airflow UI available at http://localhost:8090"
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

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    local admin_pass=""
    [ -f "$SCRIPT_DIR/.airflow-credentials.txt" ] && \
        admin_pass=$(grep "AIRFLOW_ADMIN_PASSWORD=" "$SCRIPT_DIR/.airflow-credentials.txt" | cut -d= -f2)

    echo ""
    log_success "══════════════════════════════════════════"
    log_success " GitOps POC - Local Stack Ready!"
    log_success "══════════════════════════════════════════"
    echo ""
    echo "  Argo CD UI   →  https://localhost:8080  (make argocd-ui)"
    echo "  Airflow UI   →  http://localhost:8090   (admin / ${admin_pass:-see .airflow-credentials.txt})"
    echo "  MySQL DB     →  127.0.0.1:3306          (see .mysql-credentials.txt)"
    echo "  Git repo     →  ${REPO_URL}"
    echo ""
    echo "  make status      – component health"
    echo "  make logs        – tail logs"
    echo "  make dev-down    – tear everything down"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    log_info "Starting local GitOps POC..."
    check_prerequisites     || exit 1
    verify_repo_access      || exit 1
    create_kind_cluster     || exit 1
    build_dag_sync          || exit 1
    install_ingress_nginx   || exit 1
    install_argocd          || exit 1
    create_namespaces       || exit 1
    create_mysql_secret     || exit 1
    create_airflow_secret   || exit 1
    bootstrap_argocd        || exit 1
    patch_child_apps        || exit 1
    wait_for_airflow        || true
    setup_airflow_portforward || true
    setup_mysql_portforward   || true
    print_summary
}

main "$@"

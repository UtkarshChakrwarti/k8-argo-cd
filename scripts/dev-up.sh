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
ARGOCD_NAMESPACE="argocd"
MYSQL_NAMESPACE="mysql"
AIRFLOW_NAMESPACE="airflow"
KIND_CONFIG="/tmp/kind-config.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="${REPO_URL:-}"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Preflight checks
check_prerequisites() {
    log_info "Checking for required tools..."
    
    local missing_tools=()
    
    for tool in docker kubectl kind argocd; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        return 1
    fi
    
    log_success "All required tools found"
    
    # Check if docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi
    log_success "Docker daemon is running"
}

# Resolve REPO_URL
resolve_repo_url() {
    if [ -z "$REPO_URL" ]; then
        log_info "REPO_URL not set, resolving from git remote..."
        
        # Get origin URL and convert ssh to https
        local git_url=$(cd "$SCRIPT_DIR" && git remote get-url origin)
        
        # Convert git@github.com:user/repo.git to https://github.com/user/repo.git
        REPO_URL=$(echo "$git_url" | sed 's|git@\([^:]*\):\(.*\)\.git|https://\1/\2.git|g')
        
        if [ "$REPO_URL" == "$git_url" ] && [[ "$git_url" != https* ]]; then
            log_warning "Could not convert git URL to https: $git_url"
            log_info "Please set REPO_URL environment variable manually"
            return 1
        fi
        
        log_success "Resolved REPO_URL: $REPO_URL"
    fi
}

# Create kind cluster
create_kind_cluster() {
    log_info "Creating kind cluster: $CLUSTER_NAME"
    
    # Check if cluster already exists
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        log_warning "Kind cluster '$CLUSTER_NAME' already exists, skipping creation"
        return 0
    fi
    
    # Create kind config with ingress-ready support, port mappings, and
    # extraMounts so the local dags/ folder is available inside the cluster
    # at /dags-host on every node (used by the dag-sync sidecar).
    cat > "$KIND_CONFIG" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $CLUSTER_NAME
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
    
    kind create cluster --config "$KIND_CONFIG" || {
        log_error "Failed to create kind cluster"
        return 1
    }
    
    log_success "Kind cluster created successfully"
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    kubectl cluster-info --context "kind-$CLUSTER_NAME" > /dev/null 2>&1
    log_success "Cluster is ready"
}

# Install ingress-nginx
install_ingress_nginx() {
    log_info "Installing ingress-nginx for kind..."
    
    if kubectl get ns ingress-nginx &> /dev/null; then
        log_warning "ingress-nginx namespace already exists, skipping installation"
        return 0
    fi
    
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml || {
        log_error "Failed to install ingress-nginx"
        return 1
    }
    
    # Wait for ingress-nginx to be ready
    log_info "Waiting for ingress-nginx to be ready..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s || {
        log_warning "Timeout waiting for ingress-nginx, continuing anyway..."
    }
    
    log_success "ingress-nginx installed successfully"
}

# Install Argo CD
install_argocd() {
    log_info "Installing Argo CD..."
    
    if kubectl get ns "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_warning "Argo CD namespace already exists, checking if installed..."
        if kubectl get deployment -n "$ARGOCD_NAMESPACE" argocd-server &> /dev/null; then
            log_warning "Argo CD already installed, skipping installation"
            return 0
        fi
    fi
    
    # Create namespace
    kubectl create namespace "$ARGOCD_NAMESPACE" || true
    
    # Install Argo CD using server-side apply
    kubectl apply -n "$ARGOCD_NAMESPACE" \
        --server-side \
        --force-conflicts \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || {
        log_error "Failed to install Argo CD"
        return 1
    }
    
    # Wait for Argo CD to be ready
    log_info "Waiting for Argo CD to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server -n "$ARGOCD_NAMESPACE" || {
        log_warning "Timeout waiting for Argo CD server, continuing anyway..."
    }
    
    log_success "Argo CD installed successfully"
}

# Create namespaces
create_namespaces() {
    log_info "Creating namespaces..."
    
    for ns in "$MYSQL_NAMESPACE" "$AIRFLOW_NAMESPACE"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            log_warning "Namespace '$ns' already exists"
        else
            kubectl create namespace "$ns"
            log_success "Created namespace '$ns'"
        fi
    done
}

# Create MySQL secrets
create_mysql_secret() {
    log_info "Creating MySQL secrets..."
    
    # Generate random passwords if not already set
    MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(openssl rand -base64 32)}"
    AIRFLOW_DB_PASSWORD="${AIRFLOW_DB_PASSWORD:-$(openssl rand -base64 32)}"
    
    # Check if secret already exists
    if kubectl get secret mysql-secret -n "$MYSQL_NAMESPACE" &> /dev/null; then
        log_warning "MySQL secret already exists, skipping creation"
    else
        kubectl create secret generic mysql-secret \
            --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
            --from-literal=airflow-password="$AIRFLOW_DB_PASSWORD" \
            -n "$MYSQL_NAMESPACE" || {
            log_error "Failed to create MySQL secret"
            return 1
        }
        log_success "MySQL secret created"
    fi
    
    # Save passwords to a local file for reference (with warning)
    cat > "$SCRIPT_DIR/.mysql-credentials.txt" <<EOF
# MySQL Credentials (DO NOT COMMIT THIS FILE)
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
AIRFLOW_DB_PASSWORD=$AIRFLOW_DB_PASSWORD
EOF
    chmod 600 "$SCRIPT_DIR/.mysql-credentials.txt"
    log_warning "MySQL credentials saved to '$SCRIPT_DIR/.mysql-credentials.txt' (DO NOT commit this)"
}

# Create Airflow secrets
create_airflow_secret() {
    log_info "Creating Airflow secrets..."
    
    # Generate Airflow secrets if not already set
    AIRFLOW_FERNET_KEY="${AIRFLOW_FERNET_KEY:-$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")}"
    AIRFLOW_WEBSERVER_SECRET_KEY="${AIRFLOW_WEBSERVER_SECRET_KEY:-$(openssl rand -base64 32)}"
    AIRFLOW_ADMIN_PASSWORD="${AIRFLOW_ADMIN_PASSWORD:-$(openssl rand -base64 16)}"
    
    # Build SQL_ALCHEMY_CONN
    SQL_ALCHEMY_CONN="mysql+pymysql://airflow:${AIRFLOW_DB_PASSWORD}@mysql.mysql.svc.cluster.local:3306/airflow"
    
    # Check if secret already exists
    if kubectl get secret airflow-secret -n "$AIRFLOW_NAMESPACE" &> /dev/null; then
        log_warning "Airflow secret already exists, skipping creation"
    else
        kubectl create secret generic airflow-secret \
            --from-literal=AIRFLOW__CORE__SQL_ALCHEMY_CONN="$SQL_ALCHEMY_CONN" \
            --from-literal=AIRFLOW__CORE__FERNET_KEY="$AIRFLOW_FERNET_KEY" \
            --from-literal=AIRFLOW__WEBSERVER__SECRET_KEY="$AIRFLOW_WEBSERVER_SECRET_KEY" \
            --from-literal=admin-password="$AIRFLOW_ADMIN_PASSWORD" \
            -n "$AIRFLOW_NAMESPACE" || {
            log_error "Failed to create Airflow secret"
            return 1
        }
        log_success "Airflow secret created"
    fi
    
    # Save Airflow credentials
    cat > "$SCRIPT_DIR/.airflow-credentials.txt" <<EOF
# Airflow Credentials (DO NOT COMMIT THIS FILE)
AIRFLOW_FERNET_KEY=$AIRFLOW_FERNET_KEY
AIRFLOW_WEBSERVER_SECRET_KEY=$AIRFLOW_WEBSERVER_SECRET_KEY
AIRFLOW_ADMIN_PASSWORD=$AIRFLOW_ADMIN_PASSWORD
SQL_ALCHEMY_CONN=$SQL_ALCHEMY_CONN
EOF
    chmod 600 "$SCRIPT_DIR/.airflow-credentials.txt"
    log_warning "Airflow credentials saved to '$SCRIPT_DIR/.airflow-credentials.txt' (DO NOT commit this)"
}

# Bootstrap Argo CD root app
bootstrap_argocd() {
    log_info "Bootstrapping Argo CD root app..."
    
    # Check if root-app already exists
    if kubectl get application root-app -n "$ARGOCD_NAMESPACE" &> /dev/null; then
        log_warning "Root app already exists, updating with current REPO_URL..."
        kubectl patch application root-app -n "$ARGOCD_NAMESPACE" \
            --type merge \
            -p "{\"spec\":{\"source\":{\"repoURL\":\"$REPO_URL\"}}}" || {
            log_error "Failed to patch root app"
            return 1
        }
    else
        # Create temporary file with root app and substitute REPO_URL
        # Use portable sed syntax (BSD/macOS requires '' after -i)
        local temp_app=$(mktemp)
        cat "$SCRIPT_DIR/k8s/apps/app-of-apps.yaml" > "$temp_app"
        sed -i '' "s|\${REPO_URL}|$REPO_URL|g" "$temp_app" 2>/dev/null || \
        sed -i "s|\${REPO_URL}|$REPO_URL|g" "$temp_app"
        
        kubectl create -n "$ARGOCD_NAMESPACE" -f "$temp_app" || {
            log_error "Failed to create root app"
            rm "$temp_app"
            return 1
        }
        rm "$temp_app"
    fi
    
    log_success "Argo CD root app bootstrapped"
}

# Patch child apps with repo URL
patch_child_apps() {
    log_info "Patching child apps with REPO_URL..."
    
    for app in mysql-app airflow-app; do
        # Create temporary file with app and substitute REPO_URL
        # Use portable sed syntax (BSD/macOS requires '' after -i)
        local temp_app=$(mktemp)
        cat "$SCRIPT_DIR/k8s/apps/${app}.yaml" > "$temp_app"
        sed -i '' "s|\${REPO_URL}|$REPO_URL|g" "$temp_app" 2>/dev/null || \
        sed -i "s|\${REPO_URL}|$REPO_URL|g" "$temp_app"
        
        # Check if app already exists
        if kubectl get application "$app" -n "$ARGOCD_NAMESPACE" &> /dev/null; then
            # Update existing app
            kubectl patch application "$app" -n "$ARGOCD_NAMESPACE" \
                --type merge \
                -p "{\"spec\":{\"source\":{\"repoURL\":\"$REPO_URL\"}}}" || {
                log_error "Failed to patch $app"
                rm "$temp_app"
                return 1
            }
        else
            # Create new app
            kubectl create -n "$ARGOCD_NAMESPACE" -f "$temp_app" || {
                log_error "Failed to create $app"
                rm "$temp_app"
                return 1
            }
        fi
        
        rm "$temp_app"
        log_success "Patched $app"
    done
}

# Wait for sync
wait_for_sync() {
    log_info "Waiting for applications to sync..."
    
    # Give Argo CD a moment to start syncing
    sleep 5
    
    # Simple wait - just give it time to self-heal
    log_info "Waiting for deployments to be ready (this may take a minute or two)..."
    for i in {1..120}; do
        if kubectl wait --for=condition=available --timeout=5s \
            deployment/airflow-webserver -n "$AIRFLOW_NAMESPACE" &> /dev/null; then
            log_success "Airflow webserver is ready"
            break
        fi
        echo -n "."
        sleep 1
    done
}

# Print summary
print_summary() {
    log_success "========================================"
    log_success "GitOps POC setup completed successfully!"
    log_success "========================================"
    
    echo ""
    log_info "Next steps:"
    echo "  1. Access Argo CD UI:  make argocd-ui"
    echo "  2. Access Airflow UI:  make airflow-ui"
    echo "  3. Check status:       make status"
    echo "  4. Clean up:           make dev-down"
    
    echo ""
    log_info "Credentials (see ./*-credentials.txt files):"
    echo "  - MySQL root password: Check .mysql-credentials.txt"
    echo "  - Airflow admin password: Check .airflow-credentials.txt"
    
    echo ""
    log_info "Repository URL: $REPO_URL"
}

# Build and load dag-sync image into Kind
build_dag_sync() {
    log_info "Building dag-sync image..."
    docker build -t dag-sync:local "$SCRIPT_DIR/dag-sync/" || {
        log_error "Failed to build dag-sync image"
        return 1
    }
    log_success "dag-sync image built"

    log_info "Loading dag-sync image into Kind cluster..."
    kind load docker-image dag-sync:local --name "$CLUSTER_NAME" || {
        log_error "Failed to load dag-sync image into Kind"
        return 1
    }
    log_success "dag-sync image loaded into Kind"
}

# Main function
main() {
    log_info "Starting GitOps POC setup..."
    log_info "Cluster name: $CLUSTER_NAME"
    
    check_prerequisites || exit 1
    resolve_repo_url || exit 1
    create_kind_cluster || exit 1
    build_dag_sync || exit 1
    install_ingress_nginx || exit 1
    install_argocd || exit 1
    create_namespaces || exit 1
    create_mysql_secret || exit 1
    create_airflow_secret || exit 1
    bootstrap_argocd || exit 1
    patch_child_apps || exit 1
    wait_for_sync || true  # Don't fail if sync takes a bit longer
    
    print_summary
    exit 0
}

# Run main function
main "$@"

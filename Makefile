.PHONY: help dev-up dev-down status argocd-ui airflow-ui logs clean install-prereqs build-dag-sync

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

SCRIPTS_DIR := scripts
CLUSTER_NAME := gitops-poc

# Help target
help:
	@echo "$(BLUE)GitOps POC Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Setup and teardown:$(NC)"
	@echo "  make dev-up              - Start the complete GitOps POC environment"
	@echo "  make dev-down            - Tear down the environment"
	@echo "  make install-prereqs     - Install required CLIs (kind, argocd, etc.)"
	@echo ""
	@echo "$(GREEN)Information and debugging:$(NC)"
	@echo "  make status              - Show status of all components"
	@echo "  make argocd-ui           - Open Argo CD UI (requires port-forward)"
	@echo "  make airflow-ui          - Open Airflow UI (requires port-forward)"
	@echo "  make logs                - Show logs from all components"
	@echo "  make help                - Show this help message"
	@echo ""
	@echo "$(GREEN)Advanced:$(NC)"
	@echo "  make argocd-port-forward - Manually port-forward Argo CD (8080)"
	@echo "  make airflow-port-forward - Manually port-forward Airflow (8090)"
	@echo "  make validate            - Validate k8s manifests with kustomize"
	@echo "  make build-dag-sync      - Build & load dag-sync image into Kind"
	@echo "  make clean               - Remove credential files"

# Start development environment
dev-up:
	@echo "$(GREEN)Starting GitOps POC environment...$(NC)"
	@$(SCRIPTS_DIR)/dev-up.sh

# Stop development environment
dev-down:
	@echo "$(YELLOW)Tearing down GitOps POC environment...$(NC)"
	@$(SCRIPTS_DIR)/dev-down.sh

# Show status
status:
	@$(SCRIPTS_DIR)/status.sh

# Port-forward Argo CD
argocd-port-forward:
	@$(SCRIPTS_DIR)/argocd-port-forward.sh

# Port-forward Airflow
airflow-port-forward:
	@$(SCRIPTS_DIR)/airflow-port-forward.sh

# Open Argo CD UI
argocd-ui: argocd-port-forward
	@echo "$(GREEN)Opening Argo CD UI...$(NC)"
	@sleep 2
	@"$$BROWSER" https://localhost:8080 || echo "Please open https://localhost:8080 in your browser"

# Open Airflow UI
airflow-ui: airflow-port-forward
	@echo "$(GREEN)Opening Airflow UI...$(NC)"
	@sleep 2
	@"$$BROWSER" http://localhost:8090 || echo "Please open http://localhost:8090 in your browser"

# Show logs
logs:
	@echo "$(BLUE)=== Argo CD Logs ===$(NC)"
	@kubectl logs -n argocd deployment/argocd-server --tail=50 || true
	@echo ""
	@echo "$(BLUE)=== MySQL Logs ===$(NC)"
	@kubectl logs -n mysql statefulset/dev-mysql --tail=50 || true
	@echo ""
	@echo "$(BLUE)=== Airflow Webserver Logs ===$(NC)"
	@kubectl logs -n airflow deployment/dev-airflow-webserver -c webserver --tail=50 || true
	@echo ""
	@echo "$(BLUE)=== Airflow Scheduler Logs ===$(NC)"
	@kubectl logs -n airflow deployment/dev-airflow-scheduler -c scheduler --tail=50 || true
	@echo ""
	@echo "$(BLUE)=== Airflow Triggerer Logs ===$(NC)"
	@kubectl logs -n airflow deployment/dev-airflow-triggerer -c triggerer --tail=50 || true

# Validate manifests
validate:
	@echo "$(GREEN)Validating k8s manifests...$(NC)"
	@kubectl kustomize k8s/mysql/overlays/dev > /dev/null && echo "$(GREEN)✓ MySQL manifests valid$(NC)" || (echo "$(YELLOW)✗ MySQL manifests invalid$(NC)" && false)
	@kubectl kustomize k8s/airflow/overlays/dev > /dev/null && echo "$(GREEN)✓ Airflow manifests valid$(NC)" || (echo "$(YELLOW)✗ Airflow manifests invalid$(NC)" && false)
	@kubectl kustomize k8s/apps > /dev/null && echo "$(GREEN)✓ Apps manifests valid$(NC)" || (echo "$(YELLOW)✗ Apps manifests invalid$(NC)" && false)

# Clean up credentials
clean:
	@echo "$(YELLOW)Removing credential files...$(NC)"
	@rm -f .mysql-credentials.txt .airflow-credentials.txt
	@echo "$(GREEN)Cleaned up$(NC)"

# Install prerequisites
install-prereqs:
	@echo "$(GREEN)Installing prerequisites...$(NC)"
	@command -v kind >/dev/null 2>&1 || (echo "Installing kind..." && go install sigs.k8s.io/kind@latest)
	@command -v argocd >/dev/null 2>&1 || (echo "Installing argocd..." && curl -sSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 -o /usr/local/bin/argocd && chmod +x /usr/local/bin/argocd)
	@command -v kustomize >/dev/null 2>&1 || (echo "Installing kustomize..." && go install sigs.k8s.io/kustomize/kustomize/v5@latest)
	@command -v kubectl >/dev/null 2>&1 || (echo "kubectl must be installed manually or via your system package manager")
	@echo "$(GREEN)Prerequisites installed$(NC)"

# Build and load dag-sync image into Kind cluster
build-dag-sync:
	@echo "$(GREEN)Building dag-sync image...$(NC)"
	@docker build -t dag-sync:local ./dag-sync/
	@echo "$(GREEN)Loading dag-sync into Kind cluster '$(CLUSTER_NAME)'...$(NC)"
	@kind load docker-image dag-sync:local --name $(CLUSTER_NAME)
	@echo "$(GREEN)dag-sync image ready in Kind$(NC)"


setup: dev-up

# Cleanup (alias for clean)
cleanup: clean

# All info target
info: status
	@echo ""
	@echo "$(BLUE)Credentials:$(NC)"
	@if [ -f .mysql-credentials.txt ]; then echo "$(YELLOW)MySQL credentials available in .mysql-credentials.txt$(NC)"; fi
	@if [ -f .airflow-credentials.txt ]; then echo "$(YELLOW)Airflow credentials available in .airflow-credentials.txt$(NC)"; fi

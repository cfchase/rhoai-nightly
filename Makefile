# Makefile for RHOAI 3.2 Nightly GitOps
#
# Default workflow: Run targets individually and verify each step
# Autonomous workflow: make all

# Load .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

.PHONY: help check gpu cpu pull-secret icsp setup bootstrap status validate all clean configure-repo scale refresh sync-disable sync-enable dedicate-masters

# Default target - run everything
.DEFAULT_GOAL := all

help:
	@echo "RHOAI 3.2 Nightly GitOps"
	@echo ""
	@echo "Pre-GitOps Setup (each step waits for completion):"
	@echo "  make pull-secret  - Add quay.io/rhoai credentials"
	@echo "  make icsp         - Create ICSP (waits for MCP update ~10-15 min)"
	@echo "  make gpu          - Create GPU MachineSet (waits for node Ready)"
	@echo "  make cpu          - Create CPU MachineSet (waits for node Ready)"
	@echo "  make dedicate-masters - Remove worker role from master nodes"
	@echo "  make setup        - Run all above in order"
	@echo ""
	@echo "Credentials: Copy .env.example to .env and fill in values"
	@echo "             Or: QUAY_USER=x QUAY_TOKEN=y make pull-secret"
	@echo ""
	@echo "Bootstrap GitOps:"
	@echo "  make bootstrap    - Install GitOps operator + ArgoCD"
	@echo ""
	@echo "Validation:"
	@echo "  make check        - Verify cluster connection"
	@echo "  make status       - Show ArgoCD application status"
	@echo "  make validate     - Full cluster validation"
	@echo "  make refresh      - Force pull latest nightly images"
	@echo ""
	@echo "ArgoCD Sync Control:"
	@echo "  make sync-disable - Disable auto-sync on all apps (for manual changes)"
	@echo "  make sync-enable  - Re-enable auto-sync on all apps"
	@echo ""
	@echo "Autonomous:"
	@echo "  make all          - Run everything (setup + bootstrap)"
	@echo ""
	@echo "Scaling:"
	@echo "  make scale NAME=<machineset> REPLICAS=<N|+N|-N>"
	@echo "                      Scale a MachineSet (e.g., REPLICAS=2 or REPLICAS=+1)"
	@echo ""
	@echo "Configuration (for forks):"
	@echo "  make configure-repo - Update repo URLs in applicationsets"
	@echo "                        Set GITOPS_REPO_URL and GITOPS_BRANCH in .env"
	@echo ""

# Verify cluster connection
check:
	@echo "Checking cluster connection..."
	@oc whoami --show-server
	@oc get nodes

# Pre-GitOps: GPU MachineSet
gpu:
	@chmod +x scripts/create-gpu-machineset.sh
	@scripts/create-gpu-machineset.sh

# Pre-GitOps: CPU Worker MachineSet
cpu:
	@chmod +x scripts/create-cpu-machineset.sh
	@scripts/create-cpu-machineset.sh

# Pre-GitOps: Pull Secret
pull-secret:
	@chmod +x scripts/add-pull-secret.sh
	@scripts/add-pull-secret.sh

# Pre-GitOps: ICSP (triggers node restart, waits for MCP update)
icsp:
	@chmod +x scripts/create-icsp.sh
	@scripts/create-icsp.sh

# All pre-GitOps setup (pull-secret, icsp, workers, then dedicate masters)
# Each script waits for its resources to be ready before returning
setup: pull-secret icsp gpu cpu dedicate-masters
	@echo ""
	@echo "Pre-GitOps setup complete!"

# Bootstrap GitOps
bootstrap:
	@chmod +x scripts/bootstrap-gitops.sh
	@scripts/bootstrap-gitops.sh

# Show ArgoCD status
status:
	@chmod +x scripts/status.sh
	@scripts/status.sh

# Full validation
validate:
	@chmod +x scripts/validate.sh
	@scripts/validate.sh

# Full autonomous run
all: setup bootstrap
	@echo ""
	@echo "Full setup complete!"
	@echo "Next: Add components incrementally via git commits"

# Clean up (dangerous!)
clean:
	@echo "This will delete all ArgoCD applications and applicationsets!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	@oc delete applications --all -n openshift-gitops 2>/dev/null || true
	@oc delete applicationsets --all -n openshift-gitops 2>/dev/null || true

# Configure repo URLs for forks
configure-repo:
	@chmod +x scripts/configure-repo.sh
	@scripts/configure-repo.sh

# Scale a MachineSet
scale:
	@chmod +x scripts/scale-machineset.sh
	@scripts/scale-machineset.sh --name "$(NAME)" --replicas "$(REPLICAS)"

# Force refresh of nightly images
refresh:
	@echo "Refreshing RHOAI nightly images..."
	@echo "Restarting catalog pod..."
	@oc delete pod -n openshift-marketplace -l olm.catalogSource=rhoai-catalog-nightly 2>/dev/null || true
	@echo "Waiting for catalog pod to restart..."
	@sleep 5
	@oc wait --for=condition=Ready pod -n openshift-marketplace -l olm.catalogSource=rhoai-catalog-nightly --timeout=120s 2>/dev/null || true
	@echo "Restarting RHOAI operator..."
	@oc delete pod -n redhat-ods-operator -l name=rhods-operator 2>/dev/null || true
	@echo ""
	@echo "Refresh initiated! Operator will reconcile with latest images."
	@echo "Monitor with: oc get pods -n redhat-ods-operator -w"

# Disable auto-sync on all ArgoCD applications
sync-disable:
	@echo "Disabling auto-sync on all ArgoCD applications..."
	@oc get applications -n openshift-gitops -o name | xargs -I {} oc patch {} -n openshift-gitops --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
	@echo "Auto-sync disabled. You can now make manual changes."
	@echo "Re-enable with: make sync-enable"

# Re-enable auto-sync on all ArgoCD applications
sync-enable:
	@echo "Re-enabling auto-sync on all ArgoCD applications..."
	@oc get applications -n openshift-gitops -o name | xargs -I {} oc patch {} -n openshift-gitops --type=merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
	@echo "Auto-sync re-enabled."

# Remove worker role from master nodes (run after workers are Ready)
dedicate-masters:
	@echo "Checking for Ready worker nodes..."
	@WORKERS=$$(oc get nodes -l node-role.kubernetes.io/worker,!node-role.kubernetes.io/master --no-headers 2>/dev/null | grep -c " Ready" || echo 0); \
	if [ "$$WORKERS" -eq 0 ]; then \
		echo "ERROR: No dedicated worker nodes are Ready. Create workers first with 'make gpu' or 'make cpu'"; \
		exit 1; \
	fi; \
	echo "Found $$WORKERS Ready worker node(s)"
	@echo "Removing worker role from master nodes..."
	@oc label nodes -l node-role.kubernetes.io/master node-role.kubernetes.io/worker- 2>/dev/null || true
	@echo "Master nodes are now dedicated (no longer schedulable for regular workloads)"
	@oc get nodes

#!/usr/bin/env bash
#
# sync-apps.sh - Sync ArgoCD apps one-by-one in dependency order
#
# Waits for each app to be Healthy before proceeding to the next.
# This prevents overwhelming the cluster API server.
#
# Usage:
#   ./sync-apps.sh
#   SYNC_TIMEOUT=600 ./sync-apps.sh  # 10-minute timeout per app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Sync order - operators first, then their instances
SYNC_ORDER=(
    # Phase 1: Foundation
    "nfd"
    "instance-nfd"
    "nvidia-operator"
    "instance-nvidia"

    # Phase 2: Dependent Operators
    "openshift-service-mesh"
    "kueue-operator"
    "leader-worker-set"
    "instance-lws"
    "jobset-operator"
    "instance-jobset"
    "connectivity-link"
    "instance-kuadrant"

    # Phase 3: RHOAI
    "rhoai-operator"
    "instance-rhoai"
)

# Timeout for each app to become healthy (seconds)
HEALTH_TIMEOUT="${SYNC_TIMEOUT:-300}"

sync_app() {
    local app="$1"

    # Check if app exists
    if ! oc get application/"$app" -n openshift-gitops &>/dev/null; then
        log_warn "App '$app' not found, skipping"
        return 0
    fi

    log_step "Syncing: $app"

    # Enable auto-sync
    oc patch application/"$app" -n openshift-gitops --type=merge \
        -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'

    # Trigger refresh
    oc annotate application/"$app" -n openshift-gitops \
        argocd.argoproj.io/refresh=normal --overwrite

    # Wait for healthy
    log_info "Waiting for $app to be Healthy (timeout: ${HEALTH_TIMEOUT}s)..."
    local start_time=$(date +%s)
    while true; do
        local health=$(oc get application/"$app" -n openshift-gitops \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        local sync=$(oc get application/"$app" -n openshift-gitops \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

        if [[ "$health" == "Healthy" && "$sync" == "Synced" ]]; then
            log_info "$app: Synced + Healthy"
            return 0
        fi

        # Check timeout
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $HEALTH_TIMEOUT ]]; then
            log_warn "$app: Timeout after ${HEALTH_TIMEOUT}s (health=$health, sync=$sync)"
            log_warn "Continuing to next app..."
            return 0
        fi

        # Progress indicator
        printf "  %s: sync=%s health=%s (%ds)\r" "$app" "$sync" "$health" "$elapsed"
        sleep 10
    done
}

main() {
    # Verify cluster connection
    if ! oc whoami &>/dev/null; then
        log_error "Not logged into OpenShift cluster"
        exit 1
    fi

    log_info "Connected to: $(oc whoami --show-server)"
    log_info "Starting staged sync of ${#SYNC_ORDER[@]} apps..."
    log_info "Each app will wait up to ${HEALTH_TIMEOUT}s to become healthy"
    echo ""

    local success=0
    local skipped=0

    for app in "${SYNC_ORDER[@]}"; do
        if sync_app "$app"; then
            ((success++))
        else
            ((skipped++))
        fi
        echo ""
    done

    log_info "Sync complete: $success processed, $skipped skipped/warnings"

    # Show final status
    echo ""
    log_step "Final status:"
    oc get applications -n openshift-gitops \
        -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
}

main "$@"

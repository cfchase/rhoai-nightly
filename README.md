# RHOAI 3.2 Nightly GitOps

Deploy RHOAI 3.2 nightly builds using GitOps on OpenShift.

## Quick Start

### 1. Provision Cluster

Order **AWS with OpenShift Open Environment** from [demo.redhat.com](https://demo.redhat.com):

- Select region with GPU availability (us-east-2 recommended)
- Wait for provisioning email with credentials

### 2. Login

```bash
oc login --token=<token> --server=https://api.<cluster>:6443
```

### 3. Configure Credentials

```bash
cp .env.example .env
# Edit .env with your quay.io credentials for quay.io/rhoai access
```

### 4. Deploy

```bash
make
```

This runs the full setup:

1. `pull-secret` - Add quay.io/rhoai credentials
2. `icsp` - Configure registry mirror (waits ~10-15 min for node restart)
3. `gpu` - Create GPU MachineSet g5.2xlarge (waits for node Ready, autoscale 1-3)
4. `cpu` - Create CPU MachineSet m6a.4xlarge (waits for node Ready, autoscale 1-3)
5. `gitops` - Install GitOps operator + ArgoCD (waits for ready)
6. `deploy` - Deploy root app (triggers all GitOps syncs)

Optionally run `make dedicate-masters` to remove worker role from master nodes.

## Individual Steps

Run steps individually if needed:

```bash
make pull-secret      # Add credentials
make icsp             # Apply ICSP (triggers node restart)
make gpu              # Create GPU workers
make cpu              # Create CPU workers
make gitops           # Install GitOps operator + ArgoCD
make deploy           # Deploy root app
make bootstrap        # Run gitops + deploy together
```

## Validation

```bash
make check    # Verify cluster connection
make status   # Show ArgoCD app status
make validate # Full validation
```

## Other Commands

```bash
make refresh                             # Force pull latest nightly images
make scale NAME=<machineset> REPLICAS=N  # Scale a MachineSet
make sync-disable                        # Disable ArgoCD auto-sync
make sync-enable                         # Re-enable ArgoCD auto-sync
make dedicate-masters                    # Remove worker role from masters
```

## Requirements

- OpenShift 4.17+
- `oc` CLI
- quay.io credentials with access to `quay.io/rhoai` repos

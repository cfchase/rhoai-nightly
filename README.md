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
3. `cpu` - Create CPU MachineSet m6a.4xlarge (waits for node Ready, autoscale 1-3)
4. `gpu` - Create GPU MachineSet g5.2xlarge (waits for node Ready, autoscale 1-3)
5. `gitops` - Install GitOps operator + ArgoCD (waits for ready)
6. `deploy` - Deploy ArgoCD apps (sync disabled by default)
7. `sync` - Staged sync of all apps one-by-one in dependency order

Optionally run `make dedicate-masters` to remove worker role from master nodes.

## Individual Steps

Run steps individually if needed:

```bash
make pull-secret      # Add credentials
make icsp             # Apply ICSP (triggers node restart)
make cpu              # Create CPU workers
make gpu              # Create GPU workers
make setup            # Run pull-secret + icsp + cpu + gpu

make gitops           # Install GitOps operator + ArgoCD
make deploy           # Deploy ArgoCD apps (sync disabled)
make bootstrap        # Run gitops + deploy together

make sync             # Staged sync all apps in order (RECOMMENDED)
make sync-app APP=nfd # Sync a single app
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
make dedicate-masters                    # Remove worker role from masters
```

## Sync Control

After `make sync`, apps have auto-sync **ON** and will self-heal from git.

```bash
make sync-disable                        # Disable auto-sync (for manual changes)
make sync-enable                         # Re-enable auto-sync
make sync-app APP=<name>                 # Sync single app + enable auto-sync on it
```

## Requirements

- OpenShift 4.17+
- `oc` CLI
- quay.io credentials with access to `quay.io/rhoai` repos

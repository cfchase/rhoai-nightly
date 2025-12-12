# RHOAI 3.2 Nightly GitOps

Deploy RHOAI 3.2 nightly builds using GitOps on OpenShift.

## Quick Start

### 1. Provision Cluster

Order **AWS with OpenShift Open Environment** from [demo.redhat.com](https://catalog.demo.redhat.com/):

- Recommended to allocate 3 master nodes and 3 worker nodes
- Select region with GPU availability (us-east-2 recommended)
- Wait for provisioning email with credentials

### 2. Login

```bash
oc login --token=<token> --server=https://api.<cluster>:6443
```

### 3. Configure Credentials and customize any other settings

```bash
cp .env.example .env
# Edit .env with your quay.io credentials for quay.io/rhoai access
```

### 4. Deploy

```bash
make
```

Or, to disable auto-sync after deployment (for manual cluster changes):

```bash
make all sync-disable
```

`make` (or `make all`) runs three phases:

**Phase 1: `setup`** - Cluster preparation
- `pull-secret` - Add quay.io/rhoai credentials
- `icsp` - Configure registry mirror (waits ~10-15 min for node restart)
- `cpu` - Create CPU MachineSet m6a.4xlarge (waits for node Ready)
- `gpu` - Create GPU MachineSet g5.2xlarge (waits for node Ready)

**Phase 2: `bootstrap`** - GitOps installation
- `gitops` - Install GitOps operator + ArgoCD
- `deploy` - Deploy ArgoCD apps (sync disabled by default)

**Phase 3: `sync`** - Staged deployment
- Syncs all apps one-by-one in dependency order
- Enables auto-sync on each app after it's healthy

Optionally run `make dedicate-masters` to remove worker role from master nodes.

**Note:** After deployment, auto-sync is enabled. Run `make sync-disable` before making manual changes to the cluster, or ArgoCD will revert them.

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

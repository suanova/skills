# suanova-dev-vm — SUANOVA KubeVirt VM Management Skill

A Claude Code skill for managing virtual machines (VM / VMI) in the **SUANOVA KubeVirt cluster** using `kubectl` only. Create machines, check status, start/stop, SSH in, snapshot, live-migrate, delete, and batch-create VMs — all in one skill.

> Core file: `suanova-dev-vm.md` (SKILL.md). The full operation manual lives in `kubevirt-vm-user-guide.md` (repo root).

---

## Features

| Operation | Description |
|-----------|-------------|
| **Create** | Clone from a golden image; pick subnet / CPU / RAM / disk / owner label, create in one shot |
| **Inspect** | List all VMs / VMIs, filter by owner, see node / IP / status |
| **Lifecycle** | Start / stop / restart via `runStrategy` |
| **Connect** | `ssh ubuntu@<IP>` directly (no virtctl needed); console / VNC optional |
| **Snapshot & restore** | VM-level snapshots (`VirtualMachineSnapshot`), backed by RBD copy-on-write |
| **Live migrate** | Move a running VM to another node in the same subnet without downtime |
| **Delete** | Delete a VM (removes the rootdisk PVC — irreversible) |
| **Batch-create** | `VirtualMachinePool` for N identical VMs, with scale up/down |

**Scope boundary**: this skill handles **user-side** VM management only. Cluster build/config (networking, storage, snapshot infrastructure, feature gates) is admin scope (`kubevirt-cluster-admin-guide.md`) and is not covered here.

---

## Prerequisites

- **kubectl** (the only required tool; `virtctl` is optional — SSH doesn't need it)
- A **kubeconfig** that can reach the SUANOVA KubeVirt cluster
- Claude Code (the host for this skill)

Verified cluster environment:

| Item | Value |
|------|-------|
| Kubernetes | v1.35.4, 3 control-plane nodes, no taints |
| KubeVirt / CDI | v1.8.4 / v1.65.0 |
| Storage | Rook/Ceph RBD, StorageClass `ceph-rbd-kubevirt` (RWX block, live-migration capable) |
| Golden images | `default` ns: `ubuntu-22.04/24.04/26.04-server-amd64-img` |
| Subnets / NADs | `10.66.2.0/24`, `10.66.3.0/24`, one NAD + Whereabouts IPAM per subnet |
| Whereabouts pools | both subnets: **`x.x.x.200 ~ x.x.x.220`** (gateway `x.x.x.254`) |
| NAD DNS | `223.5.5.5` / `8.8.8.8` |

---

## Installation

### Option 1: Symlink (recommended — changes take effect immediately)

```bash
# 1. Clone the repo
git clone git@github.com:suanova/skills.git suanova-skills
cd suanova-skills
git checkout feat/suanova-dev-vm   # branch holding this skill (adjust if already merged)

# 2. Create the entry in ~/.claude/skills/ (skill name = directory name)
mkdir -p ~/.claude/skills/suanova-dev-vm
ln -s "$PWD/dev/plugin/kubevirt/suanova-dev-vm.md" ~/.claude/skills/suanova-dev-vm/SKILL.md
```

After installing via symlink, edits to the skill file take effect on the **next message** — no restart needed.

### Option 2: Copy (offline / don't want to track repo changes)

```bash
mkdir -p ~/.claude/skills/suanova-dev-vm
cp dev/plugin/kubevirt/suanova-dev-vm.md ~/.claude/skills/suanova-dev-vm/SKILL.md
cp kubevirt-vm-user-guide.md ~/.claude/skills/suanova-dev-vm/   # optional: ship the manual too
```

> On this machine the installed chain is `~/.claude/skills/suanova-dev-vm/` → `~/.agents/skills/suanova-dev-vm/SKILL.md` → repo file. Either symlinks or real files work at any hop.

### Configure kubeconfig

The repo root has a `kubeconfig` file (contains cluster credentials; **gitignored, not committed** — obtain/place it yourself). Either:

```bash
# A: place it at the default location
cp kubeconfig ~/.kube/config

# B: point at it via env var (per-session)
export KUBECONFIG=/path/to/skills/kubeconfig
```

---

## Verifying the install

1. After restarting / reopening a Claude Code session, type `/` — `suanova-dev-vm` should be listed.
2. Say something like "**list all VMs**" or "**开一台机器**" — the skill triggers automatically (its description carries the trigger phrases, so natural language works without naming it).

---

## Usage

### Trigger phrases (natural language works)

> VM / VMI / virtctl / kubevirt / "list the VMs" / "开一台机器" / "spin up a VM" / "migrate this VM to another node" / "check the VM status or IP"

### Common commands

```bash
# List all VMs / VMIs (with IP, node)
kubectl get vm,vmi -n default -o wide

# Filter by owner
kubectl get vm  -n default -l owner=<username>
kubectl get vmi -n default -l owner=<username> -o wide

# Start / stop a VM (runStrategy)
kubectl patch vm <vm> -n default --type merge -p '{"spec":{"runStrategy":"Always"}}'
kubectl patch vm <vm> -n default --type merge -p '{"spec":{"runStrategy":"Halted"}}'

# Force restart (delete the VMI; runStrategy Always recreates it)
kubectl delete vmi <vm> -n default

# Connect
ssh ubuntu@<vmi-ip>          # password set at creation / SSH key

# Live-migrate to another node in the same subnet
kubectl apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstanceMigration
metadata: { name: migrate-<vm> }
spec: { vmiName: <vm> }
EOF
```

Full YAML for creating VMs / Pools is in `kubevirt-vm-user-guide.md` (§3 clone VM, §5 VirtualMachinePool); the skill also embeds reference manifests.

**Just tell Claude in plain language**, e.g.:

> "Spin up an 8C16G ubuntu 24.04 on the 10.66.3 subnet, owner is me"
> "Live-migrate vm-web to another node"
> "Snapshot vm-db"
> "Create a pool called web-pool with 3 VMs, 4C8G each"

---

## Cluster facts at a glance

| Subnet | NAD | Whereabouts pool | Gateway | Nodes |
|--------|-----|------------------|---------|-------|
| 10.66.2.0/24 | `vm-underlay-10-66-2-0` | 10.66.2.200 ~ 220 | 10.66.2.254 | `10-66-2-1` (1 node, no migration) |
| 10.66.3.0/24 | `vm-underlay-10-66-3-0` | 10.66.3.200 ~ 220 | 10.66.3.254 | `10-66-3-46/47` (2 nodes, migratable) |

- Golden images: `ubuntu-22.04-server-amd64-img`(3Gi), `ubuntu-24.04-server-amd64-img`(4Gi), `ubuntu-26.04-server-amd64-img`(4Gi)
- Root disks must be **RWX + Block + `ceph-rbd-kubevirt`** (prerequisite for live migration)
- VMs should carry an `owner` label (per-person querying, accounting, cleanup)

---

## Safety notes

- **Deletes are irreversible**: `reclaimPolicy: Delete` — deleting a VM/PVC removes the underlying RBD image. The skill always re-confirms before deleting.
- **Pool scale-down deletes randomly**: lowering `replicas` may delete a middle instance. To fix the order, configure `scaleInStrategy...sortPolicy`.
- **IP changes after live migration**: Whereabouts doesn't know about migration; the migration succeeds but the external IP may change (known upstream issue). Be careful with workloads that depend on a fixed IP.
- **Guest DNS must be set explicitly**: the NAD's DNS does not reach the guest — `networkData` must include `nameservers` (suggest `223.5.5.5` / `8.8.8.8`).
- **Subnet and `nodeSelector` must match**: use the NAD for the subnet you want and pin the VM to that subnet's nodes, or scheduling fails / the VM gets a wrong-subnet IP.

---

## Reference docs

- `suanova-dev-vm.md` — this skill (SKILL.md), operational essentials + commands
- `kubevirt-vm-user-guide.md` — full Chinese user guide (YAML, snapshots, static IP, etc.)
- Cluster-admin topics (networking / storage / snapshot infrastructure, feature gates) are out of scope — hand those to the admin

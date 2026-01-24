# K3s GPU Security Test Suite (NixOS)

This folder contains a small **probe + smoke** suite for a NixOS K3s node with NVIDIA GPU support.

The intent is twofold:
1. **Show current attack surface** ("probe" mode): demonstrate what’s possible today.
2. **Prevent regressions while hardening** ("enforce" mode): fail the suite if key vectors are still possible.

The suite is intentionally "offensive". Run it only on clusters you own.

## Quick Start

```bash
./scripts/pods/run-suite.sh --mode probe --keep
```

- `--mode probe`: demonstrate current vectors (expected to succeed).
- `--keep`: leave created resources for inspection (recommended at first).

After you harden the cluster, run:

```bash
./scripts/pods/run-suite.sh --mode enforce --keep
```

## Requirements

- `kubectl` configured and able to reach the cluster (`kubectl cluster-info` works).
- A node with NVIDIA driver functioning on host (`nvidia-smi` works on the node).
- The NVIDIA device plugin should already be deployed (or you deploy it separately) so that `nvidia.com/gpu` exists on the node.

## Modes

### `--mode probe`

**Goal**: produce evidence of what is currently allowed.

Expected behavior:
- Privileged + hostPath probes typically succeed.
- Host file read attempts show what’s exposed.
- GPU smoke test must succeed.

### `--mode enforce`

**Goal**: act as a guardrail while you reduce the attack surface.

Expected behavior:
- Unsafe probes should be blocked by policy/admission (or rendered ineffective).
- Host kubeconfig should not be world-readable.
- etcd ports should not be reachable from pods.
- GPU smoke test must still succeed.

## Flags

- `--keep`
  - Leaves the namespace and pods so you can inspect logs, events, and YAML.
  - Without `--keep`, the suite deletes the namespace at exit.

- `--namespace NAME`
  - Runs the suite in a custom namespace.
  - Example: `./scripts/pods/run-suite.sh --mode probe --namespace my-tests --keep`

## What Each Check Does

All manifests live under `scripts/pods/manifests/`.

### 1) `probe-priv-hostpath-root` (privileged + hostPath `/`)

File: `scripts/pods/manifests/10-probe-privileged-hostpath-root.yaml`

What it demonstrates:
- Whether a pod can run with `privileged: true`.
- Whether a pod can mount the host root filesystem using `hostPath: /`.
- Whether it can read sensitive host files (example: `/etc/shadow`).

Why it matters:
- `privileged + hostPath` is effectively host compromise if an attacker gets code exec.

### 2) `probe-serviceaccount-token` (token presence + RBAC sanity)

File: `scripts/pods/manifests/11-probe-serviceaccount-token.yaml`

What it checks:
- Is a service account token mounted by default?
- Can the pod list secrets in its own namespace (RBAC misconfiguration indicator)?

Why it matters:
- Token mount is common by default, but you usually want `automountServiceAccountToken: false`
  for privileged system components.
- RBAC should prevent random pods from listing secrets.

### 3) `probe-host-k3s-kubeconfig` (host kubeconfig readable via hostPath)

File: `scripts/pods/manifests/12-probe-host-k3s-kubeconfig.yaml`

What it checks:
- Whether the host’s `/etc/rancher/k3s/k3s.yaml` is readable via a `hostPath` mount.

Why it matters:
- If kubeconfig is world-readable on the host (e.g. `0644`), any local user can access the API.
- If `hostPath` mounts are allowed, a compromised pod may also read kubeconfig directly.

### 4) `probe-node-ports` (reachability from pods)

File: `scripts/pods/manifests/13-probe-node-ports.yaml`

What it checks (from inside a pod, to the node IP):
- `6443` (Kubernetes API)
- `10250` (kubelet)
- `2379` / `2380` (etcd client/peer)

Why it matters:
- etcd ports should not be reachable from general workloads.

### 5) `smoke-gpu-nvidia-smi` (GPU workload smoke test)

File: `scripts/pods/manifests/20-smoke-gpu-nvidia-smi.yaml`

What it checks:
- Pod can schedule with `resources.limits.nvidia.com/gpu: 1`.
- Pod can run `nvidia-smi` (via host binary mount).
- Required NixOS-specific mounts are present:
  - `/run/opengl-driver` (NVML libs)
  - `/nix/store` (symlink resolution)
  - `/dev` (GPU device nodes)
  - `/run/current-system/sw/bin` (host `nvidia-smi`)

Why it matters:
- Hardening shouldn’t break actual GPU workloads.

## Comparison Table (Key Expectations)

| Area | Probe Mode | Enforce Mode |
|------|------------|--------------|
| Host kubeconfig permissions | Recorded (prints mode) | Fails if `/etc/rancher/k3s/k3s.yaml` is `0644` |
| Privileged + `hostPath: /` | Expected to succeed | Expected to be blocked |
| Read host kubeconfig via hostPath | Expected to succeed | Expected to be blocked |
| etcd port reachability (2379/2380) | Recorded | Fails if reachable from a pod |
| GPU smoke test | Must pass | Must pass |

## Typical Hardening Targets

The suite is meant to guide changes like:
- Set `--write-kubeconfig-mode 600`.
- Enforce Pod Security Admission (restricted by default, explicit exemptions for GPU system daemon namespace).
- Disallow `privileged` and dangerous `hostPath` for general workloads.
- Ensure etcd ports aren’t reachable from pods.
- Disable SA token automount where possible.

## Troubleshooting

- If GPU smoke fails, check:
  - node has `nvidia.com/gpu` allocatable (`kubectl describe node ... | grep nvidia.com/gpu`)
  - NVIDIA device plugin is Running
  - mounts are correct for NixOS (`/run/opengl-driver`, `/nix/store`, `/dev`)

- Inspect suite artifacts (when `--keep`):
  - `kubectl get pods -n <namespace>`
  - `kubectl logs -n <namespace> <pod>`
  - `kubectl describe -n <namespace> pod <pod>`

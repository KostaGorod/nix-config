# K3s Security Tests

Security and GPU smoke tests for K3s clusters on NixOS.

## Quick Start

```bash
./tests/k3s-security/run.sh --mode probe --keep
```

## Modes

| Mode | Purpose |
|------|---------|
| `probe` | Discover current attack surface (expect insecure to work) |
| `enforce` | Verify hardening is in place (expect insecure to be blocked) |

## Structure

```
tests/k3s-security/
├── run.sh              # Test runner
├── probes/             # Security attack vector tests
│   ├── privileged-hostpath.yaml   # Test privileged + hostPath access
│   ├── serviceaccount-token.yaml  # Test SA token mount + RBAC
│   ├── host-kubeconfig.yaml       # Test k3s.yaml accessibility
│   └── node-ports.yaml            # Test etcd/kubelet port access
└── smoke/              # Functionality tests
    └── nvidia-smi.yaml # GPU workload with NixOS mounts
```

## Options

```
--mode probe|enforce  Test mode (default: probe)
--namespace NAME      Kubernetes namespace (default: k3s-security-tests)
--keep                Keep resources after test for inspection
```

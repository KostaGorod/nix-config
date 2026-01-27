#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/pods/run-suite.sh [--mode probe|enforce] [--namespace NAME] [--keep]

Modes:
  probe    Expect insecure capabilities to work (demonstrate vectors).
  enforce  Expect insecure capabilities to be blocked (future hardening).

This suite creates a namespace and runs:
  - privileged+hostPath probe (host filesystem read access)
  - serviceaccount token probe (sanity-check RBAC)
  - node port reachability probe (6443/10250/2379/2380)
  - GPU smoke pod (nvidia-smi via host mounts)

By default resources are cleaned up on success.
Use --keep to leave objects for inspection.
EOF
}

MODE="probe"
NAMESPACE="k3s-gpu-tests"
KEEP="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"; shift 2 ;;
    --namespace)
      NAMESPACE="$2"; shift 2 ;;
    --keep)
      KEEP="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "probe" && "$MODE" != "enforce" ]]; then
  echo "Invalid --mode: $MODE (expected probe|enforce)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$SCRIPT_DIR/manifests"

kubectl version --client >/dev/null
kubectl cluster-info >/dev/null

fail() {
  echo "FAIL: $*" >&2
  echo "Keeping resources for inspection (use --keep=false to auto-clean)." >&2
  KEEP="true"
  exit 1
}

cleanup() {
  if [[ "$KEEP" == "true" ]]; then
    return 0
  fi
  kubectl delete namespace "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
}

trap cleanup EXIT

host_k3s_kubeconfig_mode() {
  local path="/etc/rancher/k3s/k3s.yaml"
  if [[ ! -e "$path" ]]; then
    echo ""
    return 0
  fi
  stat -c '%a' "$path"
}

echo "=== host: /etc/rancher/k3s/k3s.yaml mode ==="
host_mode="$(host_k3s_kubeconfig_mode)"
if [[ -z "$host_mode" ]]; then
  echo "[host] k3s kubeconfig not found"
else
  echo "[host] K3S_KUBECONFIG_MODE=$host_mode"
  if [[ "$MODE" == "enforce" && "$host_mode" == "644" ]]; then
    fail "k3s kubeconfig is world-readable (mode=644)"
  fi
fi

if [[ "$NAMESPACE" == "k3s-gpu-tests" ]]; then
  kubectl apply -f "$MANIFEST_DIR/00-namespace.yaml" >/dev/null
else
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
fi

run_pod_and_wait() {
  local name="$1"
  local timeout="$2"

  kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$name" --timeout="$timeout" >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$name" --timeout="$timeout" >/dev/null 2>&1 || true

  local phase
  phase="$(kubectl -n "$NAMESPACE" get pod "$name" -o jsonpath='{.status.phase}')"
  echo "$phase"
}

print_logs() {
  local name="$1"
  echo "--- logs: $NAMESPACE/$name ---"
  kubectl -n "$NAMESPACE" logs "$name" || true
}

echo "=== probe: privileged+hostPath ==="
if [[ "$MODE" == "probe" ]]; then
  kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR/10-probe-privileged-hostpath-root.yaml" >/dev/null
  phase="$(run_pod_and_wait "probe-priv-hostpath-root" "60s")"
  print_logs "probe-priv-hostpath-root"
  if [[ "$phase" != "Succeeded" ]]; then
    fail "probe-priv-hostpath-root did not succeed (phase=$phase)"
  fi

  kubeconfig_mode="$(kubectl -n "$NAMESPACE" logs "probe-priv-hostpath-root" | sed -n 's/^\[probe\] K3S_KUBECONFIG_MODE=//p' | tail -n 1)"
  if [[ -n "$kubeconfig_mode" ]]; then
    echo "[probe] observed kubeconfig mode via hostPath: ${kubeconfig_mode}"
  fi
else
  set +e
  kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR/10-probe-privileged-hostpath-root.yaml" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    phase="$(run_pod_and_wait "probe-priv-hostpath-root" "30s")"
    print_logs "probe-priv-hostpath-root"
    fail "probe-priv-hostpath-root was allowed (phase=$phase); expected blocked"
  fi
fi

echo "=== probe: serviceaccount token + RBAC ==="
kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR/11-probe-serviceaccount-token.yaml" >/dev/null
phase="$(run_pod_and_wait "probe-serviceaccount-token" "60s")"
print_logs "probe-serviceaccount-token"
if [[ "$phase" != "Succeeded" ]]; then
  fail "probe-serviceaccount-token did not succeed (phase=$phase)"
fi

if [[ "$MODE" == "probe" ]]; then
  if ! kubectl -n "$NAMESPACE" logs "probe-serviceaccount-token" | grep -q "\[probe\] SA_TOKEN_PRESENT=yes"; then
    fail "probe-serviceaccount-token: SA token not mounted (unexpected for default config)"
  fi
fi

if [[ "$MODE" == "enforce" ]]; then
  if kubectl -n "$NAMESPACE" logs "probe-serviceaccount-token" | grep -q "\[probe\] LIST_SECRETS_HTTP_CODE=200"; then
    fail "probe-serviceaccount-token: was able to list secrets (RBAC misconfigured)"
  fi
fi

echo "=== probe: host kubeconfig hostPath ==="
if [[ "$MODE" == "probe" ]]; then
  kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR/12-probe-host-k3s-kubeconfig.yaml" >/dev/null
  phase="$(run_pod_and_wait "probe-host-k3s-kubeconfig" "60s")"
  print_logs "probe-host-k3s-kubeconfig"
  if [[ "$phase" != "Succeeded" ]]; then
    fail "probe-host-k3s-kubeconfig did not succeed (phase=$phase)"
  fi
  if ! kubectl -n "$NAMESPACE" logs "probe-host-k3s-kubeconfig" | grep -q "\[probe\] HOST_K3S_KUBECONFIG_PRESENT=yes"; then
    fail "probe-host-k3s-kubeconfig: host kubeconfig not readable"
  fi
else
  set +e
  kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR/12-probe-host-k3s-kubeconfig.yaml" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    phase="$(run_pod_and_wait "probe-host-k3s-kubeconfig" "60s")"
    print_logs "probe-host-k3s-kubeconfig"

    if kubectl -n "$NAMESPACE" logs "probe-host-k3s-kubeconfig" | grep -q "\[probe\] HOST_K3S_KUBECONFIG_PRESENT=yes"; then
      fail "probe-host-k3s-kubeconfig: host kubeconfig still readable"
    fi
  fi
fi

echo "=== probe: node ports ==="
kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR/13-probe-node-ports.yaml" >/dev/null
phase="$(run_pod_and_wait "probe-node-ports" "60s")"
print_logs "probe-node-ports"
if [[ "$phase" != "Succeeded" ]]; then
  fail "probe-node-ports did not succeed (phase=$phase)"
fi
if [[ "$MODE" == "enforce" ]]; then
  if kubectl -n "$NAMESPACE" logs "probe-node-ports" | grep -q "\[probe\] PORT_2379=OPEN"; then
    fail "probe-node-ports: etcd client port 2379 reachable from pod"
  fi
  if kubectl -n "$NAMESPACE" logs "probe-node-ports" | grep -q "\[probe\] PORT_2380=OPEN"; then
    fail "probe-node-ports: etcd peer port 2380 reachable from pod"
  fi
fi

echo "=== smoke: gpu nvidia-smi ==="
kubectl -n "$NAMESPACE" apply -f "$MANIFEST_DIR/20-smoke-gpu-nvidia-smi.yaml" >/dev/null
phase="$(run_pod_and_wait "smoke-gpu-nvidia-smi" "120s")"
print_logs "smoke-gpu-nvidia-smi"

if [[ "$phase" != "Succeeded" ]]; then
  fail "smoke-gpu-nvidia-smi did not succeed (phase=$phase)"
fi

if ! kubectl -n "$NAMESPACE" logs "smoke-gpu-nvidia-smi" | grep -q "NVIDIA-SMI"; then
  fail "smoke-gpu-nvidia-smi logs missing NVIDIA-SMI output"
fi

echo "OK: suite passed (mode=$MODE, namespace=$NAMESPACE)"

#!/usr/bin/env bash
# K3s Security Test Suite
#
# Tests K3s cluster security posture and GPU workload functionality.
# Run from any machine with kubectl access to the cluster.
#
# Usage:
#   ./tests/k3s-security/run.sh --mode probe   # Discover current attack surface
#   ./tests/k3s-security/run.sh --mode enforce # Verify hardening is in place
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
K3s Security Test Suite

Usage: $(basename "$0") [OPTIONS]

Options:
  --mode probe|enforce  Test mode (default: probe)
                        probe:   Discover attack vectors (expect insecure to work)
                        enforce: Verify hardening (expect insecure to be blocked)
  --namespace NAME      Kubernetes namespace (default: k3s-security-tests)
  --keep                Keep resources after test for inspection
  -h, --help            Show this help

Examples:
  $(basename "$0") --mode probe --keep     # Discover vectors, keep pods
  $(basename "$0") --mode enforce          # Verify hardening

Test Categories:
  probes/   Security attack vector tests
  smoke/    GPU workload functionality tests
EOF
}

MODE="probe"
NAMESPACE="k3s-security-tests"
KEEP="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)     MODE="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --keep)     KEEP="true"; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "Unknown: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$MODE" == "probe" || "$MODE" == "enforce" ]] || { echo "Invalid mode: $MODE" >&2; exit 2; }

kubectl version --client >/dev/null
kubectl cluster-info >/dev/null

fail() {
  echo "FAIL: $*" >&2
  KEEP="true"
  exit 1
}

cleanup() {
  [[ "$KEEP" == "true" ]] && return 0
  kubectl delete namespace "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_pod_and_wait() {
  local name="$1" timeout="$2"
  kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$name" --timeout="$timeout" >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$name" --timeout="$timeout" >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" get pod "$name" -o jsonpath='{.status.phase}'
}

logs() {
  echo "--- $1 ---"
  kubectl -n "$NAMESPACE" logs "$1" || true
}

# Create namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

#
# SECURITY PROBES
#

echo "=== [probe] privileged + hostPath ==="
if [[ "$MODE" == "probe" ]]; then
  kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/probes/privileged-hostpath.yaml" >/dev/null
  phase="$(run_pod_and_wait "probe-privileged-hostpath" "60s")"
  logs "probe-privileged-hostpath"
  [[ "$phase" == "Succeeded" ]] || fail "privileged-hostpath failed (phase=$phase)"
else
  if kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/probes/privileged-hostpath.yaml" >/dev/null 2>&1; then
    phase="$(run_pod_and_wait "probe-privileged-hostpath" "30s")"
    logs "probe-privileged-hostpath"
    fail "privileged-hostpath was allowed; expected blocked"
  fi
  echo "BLOCKED (expected)"
fi

echo "=== [probe] serviceaccount token ==="
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/probes/serviceaccount-token.yaml" >/dev/null
phase="$(run_pod_and_wait "probe-serviceaccount-token" "60s")"
logs "probe-serviceaccount-token"
[[ "$phase" == "Succeeded" ]] || fail "serviceaccount-token failed (phase=$phase)"

if [[ "$MODE" == "enforce" ]]; then
  if kubectl -n "$NAMESPACE" logs "probe-serviceaccount-token" | grep -q "\[probe\] LIST_SECRETS_HTTP_CODE=200"; then
    fail "Pod can list secrets (RBAC misconfigured)"
  fi
fi

echo "=== [probe] host kubeconfig ==="
if [[ "$MODE" == "probe" ]]; then
  kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/probes/host-kubeconfig.yaml" >/dev/null
  phase="$(run_pod_and_wait "probe-host-kubeconfig" "60s")"
  logs "probe-host-kubeconfig"
  [[ "$phase" == "Succeeded" ]] || fail "host-kubeconfig failed (phase=$phase)"
else
  if kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/probes/host-kubeconfig.yaml" >/dev/null 2>&1; then
    phase="$(run_pod_and_wait "probe-host-kubeconfig" "60s")"
    if kubectl -n "$NAMESPACE" logs "probe-host-kubeconfig" | grep -q "\[probe\] HOST_K3S_KUBECONFIG_PRESENT=yes"; then
      logs "probe-host-kubeconfig"
      fail "Host kubeconfig readable via hostPath"
    fi
  fi
  echo "BLOCKED (expected)"
fi

echo "=== [probe] node ports ==="
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/probes/node-ports.yaml" >/dev/null
phase="$(run_pod_and_wait "probe-node-ports" "60s")"
logs "probe-node-ports"
[[ "$phase" == "Succeeded" ]] || fail "node-ports failed (phase=$phase)"

if [[ "$MODE" == "enforce" ]]; then
  if kubectl -n "$NAMESPACE" logs "probe-node-ports" | grep -q "\[probe\] PORT_2379=OPEN"; then
    fail "etcd port 2379 reachable from pod"
  fi
  if kubectl -n "$NAMESPACE" logs "probe-node-ports" | grep -q "\[probe\] PORT_2380=OPEN"; then
    fail "etcd port 2380 reachable from pod"
  fi
fi

#
# GPU SMOKE TESTS
#

echo "=== [smoke] nvidia-smi ==="
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/smoke/nvidia-smi.yaml" >/dev/null
phase="$(run_pod_and_wait "smoke-nvidia-smi" "120s")"
logs "smoke-nvidia-smi"

[[ "$phase" == "Succeeded" ]] || fail "nvidia-smi failed (phase=$phase)"
kubectl -n "$NAMESPACE" logs "smoke-nvidia-smi" | grep -q "NVIDIA-SMI" || fail "nvidia-smi output missing"

echo ""
echo "OK: All tests passed (mode=$MODE)"

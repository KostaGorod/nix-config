# GPU Arbiter - Dynamic GPU switching between K3s AI workloads and Windows gaming VM
#
# Usage:
#   gpu-arbiter status      - Show current GPU state
#   gpu-arbiter claim 0     - Claim GPU 0 for gaming (stops AI, starts Windows VM)
#   gpu-arbiter release 0   - Release GPU 0 back to AI (stops Windows VM)
#
# Requires host-specific config override in /etc/gpu-arbiter/config
{
  config,
  pkgs,
  lib,
  ...
}:

let
  gpu-arbiter = pkgs.writeShellScriptBin "gpu-arbiter" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Paths and dependencies
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.pciutils
        pkgs.kmod
        pkgs.libvirt
        pkgs.kubectl
        pkgs.jq
        pkgs.procps
        pkgs.gnugrep
        pkgs.gawk
        config.boot.kernelPackages.nvidia_x11 # nvidia-smi
      ]
    }:$PATH"

    CONFIG_FILE="/etc/gpu-arbiter/config"
    if [[ -f "$CONFIG_FILE" ]]; then
      source "$CONFIG_FILE"
    else
      echo "Error: Config file $CONFIG_FILE not found" >&2
      echo "Create it with GPU_PCI and VM_NAMES arrays" >&2
      exit 1
    fi

    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
    error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

    verify_gpu_idle() {
      local pci="$1"
      # Check if any processes are using the GPU via nvidia-smi
      if nvidia-smi --query-compute-apps=pid --format=csv,noheader -i "$pci" 2>/dev/null | grep -q .; then
        return 1
      fi
      # Also check graphics processes
      if nvidia-smi --query-graphics-apps=pid --format=csv,noheader -i "$pci" 2>/dev/null | grep -q .; then
        return 1
      fi
      return 0
    }

    claim_gpu() {
      local gpu_index="$1"
      local pci_addr="''${GPU_PCI[$gpu_index]:-}"
      local vm_name="''${VM_NAMES[$gpu_index]:-}"
      
      if [[ -z "$pci_addr" ]]; then
        error "No PCI address defined for GPU index $gpu_index"
        exit 1
      fi

      log "=== Starting Claim Transaction for GPU $gpu_index ($pci_addr) ==="

      # Phase 1: Admission Control (Cordon)
      log "Phase 1: Cordoning node $NODE_NAME to prevent new GPU scheduling"
      kubectl cordon "$NODE_NAME" 2>/dev/null || log "Warning: Failed to cordon (K3s may not be running)"

      # Phase 2: Eviction (Taint)
      log "Phase 2: Adding NoExecute taint to evict AI pods"
      kubectl taint nodes "$NODE_NAME" "gpu-$gpu_index=gaming:NoExecute" --overwrite 2>/dev/null || true
      kubectl label nodes "$NODE_NAME" "gpu-$gpu_index-status=draining" --overwrite 2>/dev/null || true

      # Phase 3: Wait for idle with timeout
      log "Phase 3: Waiting for GPU to be released by AI workloads (max 120s)"
      local timeout_sec=120
      local elapsed=0
      while ! verify_gpu_idle "$pci_addr"; do
        if [[ $elapsed -ge $timeout_sec ]]; then
          error "Timeout waiting for GPU to become idle. Rolling back taint."
          kubectl taint nodes "$NODE_NAME" "gpu-$gpu_index=gaming:NoExecute-" 2>/dev/null || true
          kubectl uncordon "$NODE_NAME" 2>/dev/null || true
          kubectl label nodes "$NODE_NAME" "gpu-$gpu_index-status=available" --overwrite 2>/dev/null || true
          exit 1
        fi
        log "  GPU still in use, waiting... ($elapsed/$timeout_sec s)"
        sleep 5
        elapsed=$((elapsed + 5))
      done
      log "GPU $pci_addr is now idle"

      # Phase 4: Driver Switch with Rollback
      log "Phase 4: Switching driver from nvidia to vfio-pci"
      kubectl label nodes "$NODE_NAME" "gpu-$gpu_index-status=switching" --overwrite 2>/dev/null || true
      
      # Prepare bind
      if ! echo "vfio-pci" > "/sys/bus/pci/devices/$pci_addr/driver_override"; then
        error "Failed to set driver_override for $pci_addr"
        kubectl taint nodes "$NODE_NAME" "gpu-$gpu_index=gaming:NoExecute-" 2>/dev/null || true
        kubectl uncordon "$NODE_NAME" 2>/dev/null || true
        exit 1
      fi

      # Unbind from nvidia
      if [[ -d "/sys/bus/pci/devices/$pci_addr/driver" ]]; then
        local current_driver=$(basename $(readlink "/sys/bus/pci/devices/$pci_addr/driver"))
        if [[ "$current_driver" == "nvidia" ]]; then
          log "  Unbinding from nvidia driver..."
          if ! echo "$pci_addr" > /sys/bus/pci/drivers/nvidia/unbind; then
            error "Failed to unbind nvidia from $pci_addr"
            kubectl uncordon "$NODE_NAME" 2>/dev/null || true
            exit 1
          fi
        fi
      fi

      # Bind to vfio-pci
      log "  Binding to vfio-pci driver..."
      if ! echo "$pci_addr" > /sys/bus/pci/drivers/vfio-pci/bind; then
        error "Failed to bind vfio-pci to $pci_addr. Attempting rollback to nvidia."
        echo "" > "/sys/bus/pci/devices/$pci_addr/driver_override"
        echo "$pci_addr" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || error "Rollback bind failed!"
        kubectl taint nodes "$NODE_NAME" "gpu-$gpu_index=gaming:NoExecute-" 2>/dev/null || true
        kubectl uncordon "$NODE_NAME" 2>/dev/null || true
        kubectl label nodes "$NODE_NAME" "gpu-$gpu_index-status=error" --overwrite 2>/dev/null || true
        exit 1
      fi

      # Final Verification of driver
      sleep 1
      if [[ -L "/sys/bus/pci/devices/$pci_addr/driver" ]]; then
        local active_driver=$(basename $(readlink "/sys/bus/pci/devices/$pci_addr/driver"))
        if [[ "$active_driver" != "vfio-pci" ]]; then
          error "Driver mismatch after bind: expected vfio-pci, got $active_driver"
          exit 1
        fi
      fi

      # Phase 5: VM Start
      log "Phase 5: Starting Gaming VM: $vm_name"
      if ! virsh start "$vm_name" 2>/dev/null; then
        error "Failed to start VM $vm_name. Driver remains in vfio-pci. Manual intervention required."
        kubectl label nodes "$NODE_NAME" "gpu-$gpu_index-status=error-vm" --overwrite 2>/dev/null || true
        exit 1
      fi

      # Update State
      kubectl label nodes "$NODE_NAME" "gpu-$gpu_index-status=gaming" --overwrite 2>/dev/null || true
      log "=== GPU $gpu_index successfully claimed for gaming ==="
    }

    release_gpu() {
      local gpu_index="$1"
      local pci_addr="''${GPU_PCI[$gpu_index]:-}"
      local vm_name="''${VM_NAMES[$gpu_index]:-}"
      
      log "=== Releasing GPU $gpu_index ($pci_addr) ==="

      # Phase 1: Stop VM
      log "Phase 1: Shutting down VM $vm_name"
      virsh shutdown "$vm_name" 2>/dev/null || true
      
      log "  Waiting for VM to stop (max 30s)..."
      local count=0
      while virsh list --name 2>/dev/null | grep -q "^$vm_name$"; do
        if [[ $count -ge 30 ]]; then
          log "  Force destroying VM $vm_name..."
          virsh destroy "$vm_name" 2>/dev/null || true
          break
        fi
        sleep 2
        count=$((count + 2))
      done

      # Phase 2: Driver Switch Back
      log "Phase 2: Switching driver back to nvidia"
      echo "$pci_addr" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || log "Warning: unbind vfio failed"
      echo "" > "/sys/bus/pci/devices/$pci_addr/driver_override"
      
      if ! echo "$pci_addr" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null; then
        # Try probing instead
        log "  Direct bind failed, trying driver probe..."
        echo "$pci_addr" > /sys/bus/pci/drivers_probe || {
          error "Failed to re-bind nvidia to $pci_addr"
          kubectl label nodes "$NODE_NAME" "gpu-$gpu_index-status=error-rebind" --overwrite 2>/dev/null || true
          exit 1
        }
      fi

      # Phase 3: Restore Scheduling
      log "Phase 3: Removing NoExecute taint and uncordoning node"
      kubectl taint nodes "$NODE_NAME" "gpu-$gpu_index=gaming:NoExecute-" 2>/dev/null || true
      kubectl uncordon "$NODE_NAME" 2>/dev/null || true
      
      kubectl label nodes "$NODE_NAME" "gpu-$gpu_index-status=available" --overwrite 2>/dev/null || true
      log "=== GPU $gpu_index successfully released to AI workloads ==="
    }

    status() {
      echo "=== GPU Arbiter Status ($NODE_NAME) ==="
      echo ""
      for i in "''${!GPU_PCI[@]}"; do
        local pci="''${GPU_PCI[$i]}"
        local driver="unbound"
        if [[ -L "/sys/bus/pci/devices/$pci/driver" ]]; then
          driver=$(basename $(readlink "/sys/bus/pci/devices/$pci/driver"))
        fi
        local k8s_label=$(kubectl get node "$NODE_NAME" -o jsonpath="{.metadata.labels.gpu-$i-status}" 2>/dev/null || echo "unknown")
        local vm_name="''${VM_NAMES[$i]:-none}"
        
        echo "GPU $i ($pci):"
        echo "  Driver:     $driver"
        echo "  K8s Status: $k8s_label"
        echo "  VM Name:    $vm_name"
        
        if [[ "$driver" == "vfio-pci" ]] && [[ -n "$vm_name" ]]; then
          local vm_state=$(virsh domstate "$vm_name" 2>/dev/null || echo "not defined")
          echo "  VM State:   $vm_state"
        fi
        echo ""
      done
    }

    case "''${1:-status}" in
      claim)   claim_gpu "''${2:?GPU index required}" ;;
      release) release_gpu "''${2:?GPU index required}" ;;
      status)  status ;;
      *)       echo "Usage: gpu-arbiter {claim|release|status} [gpu_index]" ;;
    esac
  '';

in
{
  environment.systemPackages = [ gpu-arbiter ];

  # Default placeholder config - MUST be overridden in host config
  environment.etc."gpu-arbiter/config" = {
    mode = "0640";
    text = ''
      # GPU Arbiter Configuration
      # Override this in your host configuration

      declare -A GPU_PCI
      declare -A VM_NAMES
      NODE_NAME="$(hostname)"

      # Example (override in host config):
      # GPU_PCI[0]="0000:06:00.0"
      # VM_NAMES[0]="windows-gaming"
    '';
  };
}

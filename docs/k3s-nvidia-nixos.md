# K3s with NVIDIA GPU Support on NixOS

This document captures the lessons learned from getting NVIDIA GPU support working in K3s on NixOS.

## Overview

Getting NVIDIA GPUs to work in K3s on NixOS is non-trivial due to:
1. NixOS's unique filesystem layout (nix store paths, symlinks)
2. K3s using its own bundled containerd
3. The nvidia-container-toolkit on NixOS using CDI instead of nvidia-container-runtime

## What Works

### Final Working Configuration

#### 1. NVIDIA Driver Setup (`modules/nvidia/default.nix`)

```nix
# Use standard nvidia driver - NOT datacenter mode
services.xserver.videoDrivers = [ "nvidia" ];

hardware.nvidia = {
  modesetting.enable = true;
  powerManagement.enable = false;
  powerManagement.finegrained = false;
  open = false;  # Use proprietary driver
  nvidiaSettings = false;
  package = config.boot.kernelPackages.nvidiaPackages.production;
};

# Enable nvidia-container-toolkit
hardware.nvidia-container-toolkit = {
  enable = true;
  mount-nvidia-executables = true;
};
```

#### 2. K3s Server Configuration (`modules/k3s/server.nix`)

```nix
services.k3s = {
  enable = true;
  role = "server";
  extraFlags = toString [
    "--write-kubeconfig-mode 644"
    "--disable traefik"
    "--disable servicelb"
    "--node-name ${config.networking.hostName}"
    "--flannel-backend=vxlan"
    "--cluster-init"
  ];
  # No custom containerd config needed!
};
```

#### 3. NVIDIA Device Plugin with NixOS-Specific Mounts

The device plugin needs special volume mounts for NixOS:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
      priorityClassName: system-node-critical
      containers:
        - name: nvidia-device-plugin-ctr
          image: nvcr.io/nvidia/k8s-device-plugin:v0.17.0
          env:
            - name: DEVICE_DISCOVERY_STRATEGY
              value: "nvml"
            - name: FAIL_ON_INIT_ERROR
              value: "false"
            # CRITICAL: NixOS nvidia libraries location
            - name: LD_LIBRARY_PATH
              value: "/run/opengl-driver/lib"
          securityContext:
            privileged: true
          volumeMounts:
            - name: device-plugin
              mountPath: /var/lib/kubelet/device-plugins
            # NixOS-specific mounts
            - name: nvidia-driver
              mountPath: /run/opengl-driver
              readOnly: true
            - name: nix-store
              mountPath: /nix/store
              readOnly: true
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins
        - name: nvidia-driver
          hostPath:
            path: /run/opengl-driver
        - name: nix-store
          hostPath:
            path: /nix/store
```

#### 4. Running GPU Workloads

Pods that need GPU access require:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload
spec:
  containers:
    - name: cuda-container
      image: your-cuda-image
      resources:
        limits:
          nvidia.com/gpu: 1
      env:
        - name: LD_LIBRARY_PATH
          value: "/run/opengl-driver/lib"
      securityContext:
        privileged: true
      volumeMounts:
        - name: nvidia-driver
          mountPath: /run/opengl-driver
          readOnly: true
        - name: nix-store
          mountPath: /nix/store
          readOnly: true
        - name: dev
          mountPath: /dev
        # Optional: for nvidia-smi access
        - name: nvidia-bin
          mountPath: /host-bin
          readOnly: true
  volumes:
    - name: nvidia-driver
      hostPath:
        path: /run/opengl-driver
    - name: nix-store
      hostPath:
        path: /nix/store
    - name: dev
      hostPath:
        path: /dev
    - name: nvidia-bin
      hostPath:
        path: /run/current-system/sw/bin
```

## What Failed and Why

### 1. Datacenter Driver Mode

**Attempted:** `hardware.nvidia.datacenter.enable = true`

**Error:** `lib.meta.getExe': The first argument is of type set, but it should be a derivation instead`

**Why it failed:** The datacenter driver includes fabricmanager which requires specific hardware (Tesla, A100, H100 with NVLink). For consumer GPUs like RTX 2070 Super, the fabricmanager package evaluates to `{}` (empty set), causing the error.

**Lesson:** Only use datacenter mode for actual datacenter GPUs with NVLink/NVSwitch.

### 2. Custom Containerd Config Template with nvidia-container-runtime

**Attempted:** 
```nix
containerdConfigTemplate = ''
  {{ template "base" . }}
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia"]
    runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia".options]
    BinaryName = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime"
'';
```

**Error:** `fork/exec /nix/store/...-nvidia-container-toolkit-.../bin/nvidia-container-runtime: no such file or directory`

**Why it failed:** 
1. The `nvidia-container-toolkit` package does NOT include `nvidia-container-runtime` binary - it only provides `nvidia-ctk`
2. NixOS uses CDI (Container Device Interface) instead of nvidia-container-runtime
3. The nix store path is evaluated at build time, not at runtime on the target machine

**Lesson:** NixOS nvidia-container-toolkit uses CDI, not nvidia-container-runtime. Don't try to configure containerd with a runtime that doesn't exist.

### 3. CDI-Based Discovery

**Attempted:** `DEVICE_DISCOVERY_STRATEGY=cdi` with CDI spec mounts

**Error:** Various CDI spec parsing issues

**Why it failed:** The CDI approach requires proper containerd configuration which is complex with K3s's bundled containerd. NVML-based discovery is simpler and works without containerd changes.

**Lesson:** NVML discovery is more reliable on NixOS than CDI.

### 4. --default-runtime=nvidia Flag

**Attempted:** Adding `--default-runtime=nvidia` to K3s extraFlags

**Error:** K3s failed to start, etcd errors

**Why it failed:** K3s couldn't find the nvidia runtime because it doesn't exist as a binary.

**Lesson:** Don't use --default-runtime when the runtime binary doesn't exist.

### 5. Device Plugin Without Library Mounts

**Attempted:** Standard device plugin deployment without NixOS-specific mounts

**Error:** `Failed to initialize NVML: ERROR_LIBRARY_NOT_FOUND`

**Why it failed:** The container couldn't find `libnvidia-ml.so` which is in `/run/opengl-driver/lib` on NixOS.

**Lesson:** Always mount `/run/opengl-driver` and `/nix/store` for nvidia library access.

### 6. nvidia-smi Without /dev Mount

**Attempted:** Running nvidia-smi with libraries but without `/dev` mount

**Error:** `Failed to initialize NVML: Unknown Error`

**Why it failed:** NVML needs access to `/dev/nvidia*` device files.

**Lesson:** GPU workloads need `/dev` mounted and privileged mode.

## Key NixOS-Specific Paths

| Path | Contents |
|------|----------|
| `/run/opengl-driver/lib` | NVIDIA driver libraries (symlinks to nix store) |
| `/run/opengl-driver/bin` | Only mesa utilities, NOT nvidia-smi |
| `/run/current-system/sw/bin` | System binaries including nvidia-smi |
| `/nix/store` | Actual library files (needed for symlink resolution) |
| `/dev/nvidia*` | GPU device files |

## Verification Commands

```bash
# Check GPU is detected on host
nvidia-smi

# Check device plugin is running
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds

# Check GPU resource is available
kubectl describe node <node-name> | grep nvidia.com/gpu

# Test GPU access in a pod
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.0.0-base-ubuntu22.04 \
  --overrides='...' -- nvidia-smi
```

## Troubleshooting

### "No devices found" in device plugin
- Check nvidia driver is loaded: `lsmod | grep nvidia`
- Check nvidia-smi works on host
- Verify LD_LIBRARY_PATH is set in device plugin

### "ERROR_LIBRARY_NOT_FOUND"
- Mount `/run/opengl-driver` into the container
- Mount `/nix/store` for symlink resolution
- Set `LD_LIBRARY_PATH=/run/opengl-driver/lib`

### "Unknown runtime handler nvidia"
- Don't use RuntimeClass on NixOS - use default runtime with CDI/NVML
- nvidia-container-runtime doesn't exist as a binary on NixOS

### K3s fails to start after config change
- Reset K3s state: `sudo rm -rf /var/lib/rancher/k3s /etc/rancher/k3s /run/k3s`
- Restart: `sudo systemctl restart k3s`

## References

- [K3s Advanced Configuration](https://docs.k3s.io/advanced)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [NixOS nvidia-container-toolkit module](https://github.com/NixOS/nixpkgs/tree/master/nixos/modules/services/hardware/nvidia-container-toolkit)
- [Fang-Pen Lin's NixOS K8s GPU Guide](https://fangpenlin.com/posts/2025/03/01/nvidia-gpu-on-bare-metal-nixos-k8s-explained/)

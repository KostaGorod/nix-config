# K3s + NVIDIA GPU on NixOS

> **TL;DR**: Use NVML discovery, mount `/run/opengl-driver` + `/nix/store`, run privileged. No containerd config needed.

## The Problem

Getting NVIDIA GPUs working in K3s on NixOS. Sounds simple, took 12 attempts.

NixOS is special:
- `/run/opengl-driver` is NixOS's canonical graphics driver path (defined in `hardware/graphics.nix`) - legacy name, but official path for all GPU vendors
- No `nvidia-container-runtime` binary exists - NixOS uses CDI instead
- K3s bundles its own containerd, ignoring system containerd config

## The Graveyard

### Attempt 1: Datacenter Driver
```nix
hardware.nvidia.datacenter.enable = true;
```
**Died because**: Datacenter mode includes `fabricmanager` which needs NVLink hardware (Tesla/A100/H100). On consumer GPUs, it evaluates to `{}` and crashes with `lib.meta.getExe': The first argument is of type set`.

### Attempt 2: nvidia-container-runtime in containerd config
```nix
containerdConfigTemplate = ''
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia".options]
    BinaryName = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime"
'';
```
**Died because**: That binary doesn't exist. NixOS `nvidia-container-toolkit` only provides `nvidia-ctk`, not the runtime. The nix store path is also evaluated at build time, not on the target.

### Attempt 3: CDI-based discovery
```yaml
env:
  - name: DEVICE_DISCOVERY_STRATEGY
    value: "cdi"
```
**Died because**: CDI needs containerd configured to read CDI specs. K3s's bundled containerd doesn't, and configuring it is a rabbit hole.

### Attempt 4: --default-runtime=nvidia
```nix
extraFlags = [ "--default-runtime=nvidia" ];
```
**Died because**: K3s can't find a runtime that doesn't exist. etcd errors, nothing starts.

### Attempt 5: Device plugin without NixOS mounts
**Died because**: `Failed to initialize NVML: ERROR_LIBRARY_NOT_FOUND`. The container can't find `libnvidia-ml.so` because it's in `/run/opengl-driver/lib`, not `/usr/lib`.

### Attempt 6: nvidia-smi without /dev mount
**Died because**: `Failed to initialize NVML: Unknown Error`. NVML needs `/dev/nvidia*` device files.

## The Solution

### NVIDIA Driver (`modules/nvidia/default.nix`)

```nix
services.xserver.videoDrivers = [ "nvidia" ];

hardware.nvidia = {
  modesetting.enable = true;
  open = false;
  package = config.boot.kernelPackages.nvidiaPackages.production;
};

hardware.nvidia-container-toolkit = {
  enable = true;
  mount-nvidia-executables = true;
};
```

### K3s Server (`modules/k3s/server.nix`)

```nix
services.k3s = {
  enable = true;
  role = "server";
  extraFlags = toString [
    "--write-kubeconfig-mode 644"
    "--disable traefik"
    "--disable servicelb"
  ];
};
```

No containerd config. No runtime handlers. Just defaults.

### Device Plugin (the secret sauce)

```yaml
containers:
  - name: nvidia-device-plugin-ctr
    image: nvcr.io/nvidia/k8s-device-plugin:v0.17.0
    env:
      - name: DEVICE_DISCOVERY_STRATEGY
        value: "nvml"
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
volumes:
  - name: nvidia-driver
    hostPath:
      path: /run/opengl-driver
  - name: nix-store
    hostPath:
      path: /nix/store
```

### GPU Workloads

Same mounts, plus `/dev` for device access:

```yaml
spec:
  containers:
    - name: gpu-job
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
        - name: nix-store
          mountPath: /nix/store
        - name: dev
          mountPath: /dev
  volumes:
    - name: nvidia-driver
      hostPath: { path: /run/opengl-driver }
    - name: nix-store
      hostPath: { path: /nix/store }
    - name: dev
      hostPath: { path: /dev }
```

## Why It Works

The key insight: **NVML doesn't need containerd integration, it just needs libraries**.

On NixOS:
- `/run/opengl-driver/lib` contains symlinks to nvidia libraries in `/nix/store`
- Setting `LD_LIBRARY_PATH` tells the linker where to find them
- Mounting `/nix/store` lets those symlinks resolve
- `privileged: true` + `/dev` mount gives access to GPU device files

No CDI. No runtime handlers. No containerd config. Just library paths.

## Key Files

| File | Purpose |
|------|---------|
| `modules/nvidia/default.nix` | Driver + container-toolkit setup |
| `modules/k3s/server.nix` | K3s config (manifests for device plugin) |
| `tests/k3s-security/smoke/nvidia-smi.yaml` | GPU smoke test |

## NixOS-Specific Paths

| Path | What's There |
|------|--------------|
| `/run/opengl-driver/lib` | nvidia libraries (symlinks) |
| `/run/current-system/sw/bin` | nvidia-smi binary |
| `/nix/store` | actual library files |
| `/dev/nvidia*` | GPU devices |

## Gotchas

- Consumer GPUs (RTX series) don't support datacenter mode
- `nvidia-container-runtime` binary doesn't exist on NixOS
- CDI discovery requires containerd config K3s doesn't have
- Without `/nix/store` mount, symlinks in `/run/opengl-driver` break
- Without `LD_LIBRARY_PATH`, libraries aren't found even when mounted

## Verification

```bash
./tests/k3s-security/run.sh --mode probe
```

Expected: `smoke-nvidia-smi` passes, shows GPU info.

```bash
kubectl describe node | grep nvidia.com/gpu
```

Expected: `nvidia.com/gpu: N` in allocatable resources.

## Security Note

This setup requires `privileged: true` and `hostPath` mounts. Treat GPU nodes as trusted execution environments, not security boundaries. See `tests/k3s-security/` for attack surface probes.

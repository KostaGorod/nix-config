{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # K3S SERVER CONFIGURATION
  # With GPU support via nvidia-container-toolkit
  # =============================================================================
  
  services.k3s = {
    enable = true;
    role = "server";
    
    extraFlags = toString [
      "--write-kubeconfig-mode 644"
      "--disable traefik"           # Use custom ingress
      "--disable servicelb"         # Use MetalLB or similar
      "--node-name ${config.networking.hostName}"
      "--flannel-backend=vxlan"
      "--cluster-init"              # Initialize HA-capable cluster
      # GPU status labels (managed by gpu-arbiter)
      "--node-label=gpu-0-status=available"
    ];
  };

  # =============================================================================
  # K3S CONTAINERD CONFIG FOR NVIDIA GPU
  # K3s uses its own bundled containerd, needs custom config for nvidia runtime
  # =============================================================================
  environment.etc."rancher/k3s/config.yaml".text = ''
    # K3s configuration
  '';

  # K3s containerd config template - enables nvidia runtime
  # This file is read by K3s's bundled containerd
  environment.etc."rancher/k3s/registries.yaml".text = ''
    # Container registries config (placeholder)
  '';

  # Containerd config template for K3s with nvidia runtime
  system.activationScripts.k3s-containerd-nvidia = lib.stringAfter [ "var" ] ''
    mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
    cat > /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl << 'EOF'
[plugins."io.containerd.grpc.v1.cri"]
  enable_cdi = true
  cdi_spec_dirs = ["/etc/cdi", "/var/run/cdi"]

[plugins."io.containerd.grpc.v1.cri".containerd]
  default_runtime_name = "nvidia"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  privileged_without_host_devices = false
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
  BinaryName = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime"
EOF
  '';

  # Open ports for K3s
  networking.firewall.allowedTCPPorts = [ 6443 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];

  # =============================================================================
  # NVIDIA RuntimeClass for Kubernetes
  # Required for pods to use the nvidia container runtime
  # =============================================================================
  system.activationScripts.k3s-nvidia-runtime-class = lib.stringAfter [ "var" ] ''
    mkdir -p /var/lib/rancher/k3s/server/manifests
    cat > /var/lib/rancher/k3s/server/manifests/nvidia-runtime-class.yaml << 'EOF'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF
  '';

  # =============================================================================
  # NVIDIA Device Plugin for Kubernetes
  # Auto-deploy via K3s manifests directory
  # Uses CDI mode for GPU discovery
  # =============================================================================
  system.activationScripts.k3s-nvidia-device-plugin = lib.stringAfter [ "var" ] ''
    mkdir -p /var/lib/rancher/k3s/server/manifests
    cat > /var/lib/rancher/k3s/server/manifests/nvidia-device-plugin.yaml << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      runtimeClassName: nvidia
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
        # Tolerate gpu-arbiter gaming taint
        - key: gpu-0
          operator: Exists
          effect: NoExecute
      priorityClassName: system-node-critical
      containers:
        - name: nvidia-device-plugin-ctr
          image: nvcr.io/nvidia/k8s-device-plugin:v0.17.0
          env:
            # Use CDI for device discovery (works better with NixOS)
            - name: DEVICE_DISCOVERY_STRATEGY
              value: "cdi"
            # CDI spec is at /var/run/cdi/nvidia-container-toolkit.json
            - name: CDI_ROOT
              value: "/var/run/cdi"
            # Also set CDI_KIND to match the file name (vendor is nvidia.com)
            - name: CDI_KIND
              value: "nvidia.com/gpu"
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: device-plugin
              mountPath: /var/lib/kubelet/device-plugins
            - name: cdi
              mountPath: /var/run/cdi
              readOnly: true
            # Also mount /etc/cdi for potential configs there
            - name: cdi-etc
              mountPath: /etc/cdi
              readOnly: true
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins
        - name: cdi
          hostPath:
            path: /var/run/cdi
        - name: cdi-etc
          hostPath:
            path: /etc/cdi
            type: DirectoryOrCreate
EOF
  '';

  environment.systemPackages = with pkgs; [ 
    k3s 
    kubectl
    k9s
  ];
}

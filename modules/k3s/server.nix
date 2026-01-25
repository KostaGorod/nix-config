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
    
    # Configure containerd with nvidia runtime
    # K3s uses this template to generate containerd config
    containerdConfigTemplate = ''
      # Base K3s containerd config
      {{ template "base" . }}

      # Add nvidia container runtime for GPU workloads
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia"]
        runtime_type = "io.containerd.runc.v2"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."nvidia".options]
        BinaryName = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime"
    '';
  };
  
  # Create nvidia RuntimeClass for K3s
  # This allows pods to request the nvidia runtime via runtimeClassName: nvidia
  services.k3s.manifests.nvidia-runtime-class = {
    target = "nvidia-runtime-class.yaml";
    content = {
      apiVersion = "node.k8s.io/v1";
      kind = "RuntimeClass";
      metadata.name = "nvidia";
      handler = "nvidia";
    };
  };

  # Open ports for K3s
  networking.firewall.allowedTCPPorts = [ 6443 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];

  # =============================================================================
  # NVIDIA Device Plugin for Kubernetes
  # Uses nvml (nvidia-smi) for GPU discovery - simpler and more reliable on NixOS
  # =============================================================================
  services.k3s.manifests.nvidia-device-plugin = {
    target = "nvidia-device-plugin.yaml";
    content = {
      apiVersion = "apps/v1";
      kind = "DaemonSet";
      metadata = {
        name = "nvidia-device-plugin-daemonset";
        namespace = "kube-system";
      };
      spec = {
        selector.matchLabels.name = "nvidia-device-plugin-ds";
        updateStrategy.type = "RollingUpdate";
        template = {
          metadata.labels.name = "nvidia-device-plugin-ds";
          spec = {
            runtimeClassName = "nvidia";
            tolerations = [
              { key = "nvidia.com/gpu"; operator = "Exists"; effect = "NoSchedule"; }
              { key = "gpu-0"; operator = "Exists"; effect = "NoExecute"; }
            ];
            priorityClassName = "system-node-critical";
            containers = [{
              name = "nvidia-device-plugin-ctr";
              image = "nvcr.io/nvidia/k8s-device-plugin:v0.17.0";
              env = [
                { name = "DEVICE_DISCOVERY_STRATEGY"; value = "nvml"; }
                { name = "FAIL_ON_INIT_ERROR"; value = "false"; }
              ];
              securityContext.privileged = true;
              volumeMounts = [{
                name = "device-plugin";
                mountPath = "/var/lib/kubelet/device-plugins";
              }];
            }];
            volumes = [{
              name = "device-plugin";
              hostPath.path = "/var/lib/kubelet/device-plugins";
            }];
          };
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [ 
    k3s 
    kubectl
    k9s
  ];
}

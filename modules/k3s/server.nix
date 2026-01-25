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
    
    # No custom containerd config needed - device plugin uses NVML for GPU discovery
    # which doesn't require special containerd configuration
  };

  # Open ports for K3s
  networking.firewall.allowedTCPPorts = [ 6443 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];

  # =============================================================================
  # NVIDIA Device Plugin for Kubernetes
  # Uses NVML (nvidia-smi) for GPU discovery - works without special containerd config
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
            tolerations = [
              { key = "nvidia.com/gpu"; operator = "Exists"; effect = "NoSchedule"; }
              { key = "gpu-0"; operator = "Exists"; effect = "NoExecute"; }
            ];
            priorityClassName = "system-node-critical";
            containers = [{
              name = "nvidia-device-plugin-ctr";
              image = "nvcr.io/nvidia/k8s-device-plugin:v0.17.0";
              env = [
                # Use NVML (nvidia-smi) for device discovery
                # This works without special containerd configuration
                { name = "DEVICE_DISCOVERY_STRATEGY"; value = "nvml"; }
                { name = "FAIL_ON_INIT_ERROR"; value = "false"; }
              ];
              securityContext.privileged = true;
              volumeMounts = [
                { name = "device-plugin"; mountPath = "/var/lib/kubelet/device-plugins"; }
              ];
            }];
            volumes = [
              { name = "device-plugin"; hostPath.path = "/var/lib/kubelet/device-plugins"; }
            ];
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

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
    
    # Enable CDI support in containerd for GPU device injection
    # NixOS nvidia-container-toolkit uses CDI (not nvidia-container-runtime)
    containerdConfigTemplate = ''
      # Base K3s containerd config
      {{ template "base" . }}

      # Enable CDI (Container Device Interface) for GPU access
      # The nvidia-container-toolkit-cdi-generator service creates specs in /var/run/cdi
      [plugins."io.containerd.grpc.v1.cri"]
        enable_cdi = true
        cdi_spec_dirs = ["/var/run/cdi", "/etc/cdi"]
    '';
  };

  # Open ports for K3s
  networking.firewall.allowedTCPPorts = [ 6443 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];

  # =============================================================================
  # NVIDIA Device Plugin for Kubernetes
  # Uses CDI for device discovery (integrated with NixOS nvidia-container-toolkit)
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
            # No runtimeClassName - use default runc with CDI for device injection
            tolerations = [
              { key = "nvidia.com/gpu"; operator = "Exists"; effect = "NoSchedule"; }
              { key = "gpu-0"; operator = "Exists"; effect = "NoExecute"; }
            ];
            priorityClassName = "system-node-critical";
            containers = [{
              name = "nvidia-device-plugin-ctr";
              image = "nvcr.io/nvidia/k8s-device-plugin:v0.17.0";
              env = [
                # Use CDI for device discovery - matches NixOS nvidia-container-toolkit
                { name = "DEVICE_DISCOVERY_STRATEGY"; value = "cdi"; }
                { name = "CDI_ROOT"; value = "/var/run/cdi"; }
                { name = "FAIL_ON_INIT_ERROR"; value = "false"; }
              ];
              securityContext.privileged = true;
              volumeMounts = [
                { name = "device-plugin"; mountPath = "/var/lib/kubelet/device-plugins"; }
                { name = "cdi"; mountPath = "/var/run/cdi"; readOnly = true; }
              ];
            }];
            volumes = [
              { name = "device-plugin"; hostPath.path = "/var/lib/kubelet/device-plugins"; }
              { name = "cdi"; hostPath.path = "/var/run/cdi"; }
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

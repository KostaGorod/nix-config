{ config, pkgs, ... }:

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
      "--disable traefik" # Use custom ingress
      "--disable servicelb" # Use MetalLB or similar
      "--node-name ${config.networking.hostName}"
      "--flannel-backend=vxlan"
      "--cluster-init" # Initialize HA-capable cluster
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
  # Uses NVML (nvidia-smi) for GPU discovery
  # Requires nvidia driver libraries mounted from NixOS host paths
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
              {
                key = "nvidia.com/gpu";
                operator = "Exists";
                effect = "NoSchedule";
              }
              {
                key = "gpu-0";
                operator = "Exists";
                effect = "NoExecute";
              }
            ];
            priorityClassName = "system-node-critical";
            containers = [
              {
                name = "nvidia-device-plugin-ctr";
                image = "nvcr.io/nvidia/k8s-device-plugin:v0.17.0";
                env = [
                  # Use NVML (nvidia-smi) for device discovery
                  {
                    name = "DEVICE_DISCOVERY_STRATEGY";
                    value = "nvml";
                  }
                  {
                    name = "FAIL_ON_INIT_ERROR";
                    value = "false";
                  }
                  # NixOS-specific: nvidia libraries are in /run/opengl-driver/lib
                  {
                    name = "LD_LIBRARY_PATH";
                    value = "/run/opengl-driver/lib";
                  }
                ];
                securityContext.privileged = true;
                volumeMounts = [
                  {
                    name = "device-plugin";
                    mountPath = "/var/lib/kubelet/device-plugins";
                  }
                  # NixOS-specific mounts for nvidia driver access
                  {
                    name = "nvidia-driver";
                    mountPath = "/run/opengl-driver";
                    readOnly = true;
                  }
                  {
                    name = "nix-store";
                    mountPath = "/nix/store";
                    readOnly = true;
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "device-plugin";
                hostPath.path = "/var/lib/kubelet/device-plugins";
              }
              # NixOS-specific: nvidia driver libraries
              {
                name = "nvidia-driver";
                hostPath.path = "/run/opengl-driver";
              }
              # NixOS-specific: nix store for symlink resolution
              {
                name = "nix-store";
                hostPath.path = "/nix/store";
              }
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

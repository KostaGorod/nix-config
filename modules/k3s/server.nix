{ config, pkgs, ... }:

{
  # =============================================================================
  # K3S SERVER CONFIGURATION
  # =============================================================================
  
  services.k3s = {
    enable = true;
    role = "server";
    # If this is the first node, we initialize the cluster.
    # For subsequent nodes, we'd need --server https://<ip>:6443
    extraFlags = toString [
      "--write-kubeconfig-mode 644"
      "--disable traefik"      # We might want Nginx or Gateway API later
      "--disable servicelb"    # We'll use MetalLB or similar
      "--node-name ${config.networking.hostName}"
      "--flannel-backend=vxlan" # Default, reliable
    ];
  };

  # Open ports for K3s
  networking.firewall.allowedTCPPorts = [ 6443 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];

  environment.systemPackages = [ pkgs.k3s ];
}

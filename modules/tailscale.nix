{ config, lib, pkgs, ... }:

{
  # Tailscale VPN service configuration
  services.tailscale = {
    enable = true;
    package = pkgs.tailscale;
  };

  # Fix DNS resolution conflicts with MagicDNS
  networking.resolvconf.useLocalResolver = false;

  # Configure dnsmasq to work with Tailscale MagicDNS
  services.dnsmasq = {
    enable = true;
    settings = {
      # Listen on localhost and Tailscale interface
      listen-address = "127.0.0.1";
      # Bind to specific interfaces to prevent conflicts
      bind-interfaces = true;
      # Cache size for better performance
      cache-size = "1000";
    };
  };

  # Environment packages for Tailscale management
  environment.systemPackages = with pkgs; [
    tailscale
  ];

  # Network configuration
  networking.firewall = {
    # Allow Tailscale traffic
    trustedInterfaces = [ "tailscale0" ];
    # Allow specific ports if needed
    allowedUDPPorts = [ 41641 ]; # Default Tailscale port
  };

  # SystemD service configuration for better integration
  systemd.services.tailscaled = {
    # Ensure tailscaled starts after network is ready
    wants = [ "network-pre.target" ];
    after = [ "network-pre.target" ];
    # Restart on failure
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5";
    };
  };
}

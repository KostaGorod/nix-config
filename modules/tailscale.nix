{ config, lib, pkgs, ... }:

{
  # Tailscale VPN service configuration
  services.tailscale = {
    enable = true;
    package = pkgs.tailscale;
  };

  # Enable local DNS resolver
  networking.resolvconf.useLocalResolver = true;

  # Configure dnsmasq to work with Tailscale MagicDNS (split DNS)
  services.dnsmasq = {
    enable = true;
    settings = {
      # Listen on localhost
      listen-address = "127.0.0.1";
      # Bind to specific interfaces to prevent conflicts
      bind-interfaces = true;
      # Cache size for better performance
      cache-size = "1000";
      # Default upstream DNS servers for regular queries (Cloudflare and Google)
      server = [
        "1.1.1.1"
        "8.8.8.8"
        # Route Tailscale domains to MagicDNS
        "/myth-rudd.ts.net/100.100.100.100"
        "/int.toxiclabs.net/100.100.100.100"
        "/toxiclabs.local.lan/100.100.100.100"
      ];
      # Strict order - use servers in the order specified
      strict-order = true;
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

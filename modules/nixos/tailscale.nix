{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.tailscale-mesh;
in
{
  options.services.tailscale-mesh = {
    enable = lib.mkEnableOption "Tailscale client with MagicDNS split-DNS";

    magicDnsDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "ts.net"
        "int.toxiclabs.net"
        "toxiclabs.local.lan"
      ];
      description = "Domains routed to Tailscale MagicDNS (100.100.100.100).";
    };

    upstreamDns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "1.1.1.1"
        "8.8.8.8"
      ];
      description = "Upstream DNS for non-Tailscale queries.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      package = pkgs.tailscale;
      useRoutingFeatures = "client";
    };

    networking.resolvconf.useLocalResolver = true;

    services.dnsmasq = {
      enable = true;
      settings = {
        listen-address = "127.0.0.1";
        bind-interfaces = true;
        cache-size = "1000";
        server = cfg.upstreamDns ++ map (d: "/${d}/100.100.100.100") cfg.magicDnsDomains;
        strict-order = true;
      };
    };

    environment.systemPackages = [ pkgs.tailscale ];

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ 41641 ];
    };

    systemd.services.tailscaled = {
      wants = [ "network-pre.target" ];
      after = [ "network-pre.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5";
      };
    };
  };
}

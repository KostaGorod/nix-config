{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/k3s/server.nix
    ../../modules/nvidia/default.nix
  ];

  # =============================================================================
  # SYSTEM
  # =============================================================================
  system.stateVersion = "25.11";
  
  # Allow unfree packages (required for NVIDIA drivers, steam, etc)
  nixpkgs.config.allowUnfree = true;
  
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Enable IOMMU for GPU passthrough capability
  boot.kernelParams = [
    "amd_iommu=on"
    "iommu=pt"
  ];

  # =============================================================================
  # NETWORKING
  # =============================================================================
  networking = {
    hostName = "gpu-node-1";
    
    # Disable NetworkManager for server (use systemd-networkd)
    networkmanager.enable = false;
    useNetworkd = true;
    
    # Firewall - allow K3s ports
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22      # SSH
        6443    # K3s API server
        10250   # Kubelet
        2379    # etcd client
        2380    # etcd peer
        80      # HTTP (ingress)
        443     # HTTPS (ingress)
      ];
      allowedUDPPorts = [
        8472    # Flannel VXLAN
        51820   # WireGuard (if using)
      ];
    };
  };

  # systemd-networkd configuration for VLAN
  systemd.network = {
    enable = true;
    
    netdevs = {
      "10-vlan100" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan100";
        };
        vlanConfig.Id = 100;
      };
    };
    
    networks = {
      # Main interface - VLAN trunk
      "20-main" = {
        matchConfig.Name = "en*";  # Match ethernet interface
        vlan = [ "vlan100" ];
        networkConfig.LinkLocalAddressing = "no";
      };
      
      # K8s VLAN with static IP
      "30-vlan100" = {
        matchConfig.Name = "vlan100";
        networkConfig = {
          Address = "10.100.1.10/24";
          Gateway = "10.100.1.1";
          DNS = [ "10.100.1.1" "1.1.1.1" ];
          DHCP = "no";
        };
      };
    };
  };

  # =============================================================================
  # SERVICES
  # =============================================================================
  
  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # =============================================================================
  # USERS
  # =============================================================================
  users.users.kosta = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "video" "render" ];
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      # "ssh-ed25519 AAAA..."
    ];
  };

  # Allow wheel group to sudo without password (optional, for convenience)
  security.sudo.wheelNeedsPassword = false;

  # =============================================================================
  # PACKAGES
  # =============================================================================
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    nvtopPackages.full  # nvtop changed in recent nixpkgs
    kubectl
    k9s
    pciutils
    lshw
  ];
}

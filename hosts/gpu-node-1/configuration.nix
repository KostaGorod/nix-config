{ config, pkgs, inputs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/k3s/server.nix
    ../../modules/nvidia/default.nix
    ../../modules/nixos/vfio.nix
    ../../modules/nixos/libvirt.nix
    ../../modules/nixos/gpu-arbiter.nix
  ];

  # =============================================================================
  # SYSTEM
  # =============================================================================
  system.stateVersion = "25.11";
  
  # Allow unfree packages (required for NVIDIA drivers, steam, etc)
  nixpkgs.config.allowUnfree = true;
  
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Enable IOMMU for GPU passthrough capability (Intel vIOMMU in Proxmox VM)
  boot.kernelParams = [
    "intel_iommu=on"
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
      # Main interface - VLAN trunk + default network
      "20-main" = {
        matchConfig.Name = "en*";  # Match ethernet interface
        vlan = [ "vlan100" ];
        networkConfig = {
          DHCP = "yes";  # Default/untagged VLAN for SSH access
        };
        dhcpV4Config = {
          RouteMetric = 100;  # Lower priority than VLAN100 if both have routes
        };
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
        routes = [
          # K8s traffic uses VLAN100 gateway
          { Destination = "10.100.0.0/16"; Gateway = "10.100.1.1"; Metric = 50; }
        ];
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
    extraGroups = [ "wheel" "docker" "video" "render" "libvirtd" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtkgXu/YbIS0vS4D/gZwejFfTs5JgnzuC8mJ7458M8/ kosta@rocinante"
    ];
    hashedPassword = "$6$DEZMi88WK4aKrWfc$HNdlAblj5.KRkmizg6fffuDexQmYGLewdmiu1w1FtBRSWvQs9BSfGCv8wIJ8bive3ZSCdGW11qo4YX6dTgmPQ1";
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
    nvtopPackages.full
    kubectl
    k9s
    pciutils
    lshw
    tmux
  ];

  # =============================================================================
  # GPU ARBITER CONFIGURATION
  # Maps GPU index to PCI address and Windows VM name
  # =============================================================================
  # Override the default gpu-arbiter config with actual values
  # NOTE: Update GPU_PCI[0] with actual PCI address from: lspci -nn | grep -i nvidia
  environment.etc."gpu-arbiter/config" = {
    mode = "0640";
    user = "root";
    group = "wheel";
    text = ''
      # GPU Arbiter Configuration for gpu-node-1
      # RTX 2070 Super passed through from Proxmox
      
      declare -A GPU_PCI
      declare -A VM_NAMES
      NODE_NAME="gpu-node-1"
      
      # GPU 0: RTX 2070 Super
      # TODO: Update this with actual PCI address from: lspci -nn | grep -i nvidia
      GPU_PCI[0]="0000:01:00.0"
      
      # Windows gaming VM name (create with virt-manager)
      VM_NAMES[0]="windows-gaming"
    '';
  };

  # =============================================================================
  # GPU ARBITER ACCESS CONTROL
  # Only kosta can run gpu-arbiter (requires sudo)
  # =============================================================================
  security.sudo.extraRules = [
    {
      users = [ "kosta" ];
      commands = [
        { command = "${pkgs.libvirt}/bin/virsh *"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/gpu-arbiter *"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];

}

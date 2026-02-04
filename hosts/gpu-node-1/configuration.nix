{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/k3s/server.nix
    ../../modules/nvidia/default.nix
    ../../modules/github-runner.nix
    ../../modules/nixos/vfio.nix
    ../../modules/nixos/libvirt.nix
    ../../modules/nixos/gpu-arbiter.nix
    ../../modules/helicone/compose.nix
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
        22 # SSH (fallback when Tailscale unavailable)
        6443 # K3s API server
        10250 # Kubelet
        2379 # etcd client
        2380 # etcd peer
        80 # HTTP (ingress)
        443 # HTTPS (ingress)
      ];
      allowedUDPPorts = [
        8472 # Flannel VXLAN
        51820 # WireGuard (if using)
        # 41641 added by tailscale.nix module
      ];
      # tailscale0 added as trusted interface by tailscale.nix module
    };
  };

  # systemd-networkd configuration - simple DHCP for now
  # VLAN for K8s traffic will be added later when node-2 is set up
  systemd.network = {
    enable = true;

    networks = {
      "20-main" = {
        matchConfig.Name = "en*"; # Match ethernet interface
        networkConfig = {
          DHCP = "yes";
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
    listenAddresses = [
      {
        addr = "0.0.0.0";
        port = 22;
      } # Needed for initial setup, can be restricted later
    ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # GitHub Actions Self-Hosted Runner (GitOps deployments)
  # To enable: create token file and set enable = true
  # Get token from: https://github.com/KostaGorod/nix-config/settings/actions/runners/new
  services.github-runner-nixos = {
    enable = false; # Set to true after creating token file
    url = "https://github.com/KostaGorod/nix-config";
    tokenFile = "/run/secrets/github-runner-token";
    labels = [
      "nixos"
      "staging"
      "gpu"
    ];
  };

  # Tailscale SSH - takes over SSH authentication via Tailscale identity
  services.tailscale.extraSetFlags = [
    "--ssh"
  ];

  # Helicone LLM Observability (docker-compose)
  services.helicone = {
    enable = true;
    hostName = "gpu-node-1"; # Tailscale hostname for self-hosted URLs
    openFirewall = true;
    # Generate proper secrets for production:
    # secrets.betterAuthSecret = "$(openssl rand -hex 32)";
  };

  # =============================================================================
  # USERS
  # =============================================================================
  # Tailscale SSH users - mapped via localpart:*@github.com
  # KostaGorod@github.com -> kostagorod
  # Gonya990@github.com -> gonya

  # Base groups for GPU node users
  users.users =
    let
      gpuUserGroups = [
        "wheel"
        "docker"
        "video"
        "render"
        "libvirtd"
      ];
    in
    {
      # Primary admin user (existing)
      kosta = {
        isNormalUser = true;
        extraGroups = gpuUserGroups;
        shell = pkgs.fish;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtkgXu/YbIS0vS4D/gZwejFfTs5JgnzuC8mJ7458M8/ kosta@rocinante"
        ];
        hashedPassword = "$6$DEZMi88WK4aKrWfc$HNdlAblj5.KRkmizg6fffuDexQmYGLewdmiu1w1FtBRSWvQs9BSfGCv8wIJ8bive3ZSCdGW11qo4YX6dTgmPQ1";
      };

      # Tailscale SSH user: KostaGorod@github.com -> kostagorod
      kostagorod = {
        isNormalUser = true;
        extraGroups = gpuUserGroups;
        shell = pkgs.fish;
        # Auth handled by Tailscale SSH - no password or SSH keys needed
      };

      # Tailscale SSH user: Gonya990@github.com -> gonya
      gonya = {
        isNormalUser = true;
        extraGroups = gpuUserGroups;
        # Auth handled by Tailscale SSH - no password or SSH keys needed
      };
    };

  # Allow wheel group to sudo without password (optional, for convenience)
  security.sudo.wheelNeedsPassword = false;

  # =============================================================================
  # PACKAGES
  # =============================================================================
  # Enable fish shell
  programs.fish.enable = true;

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
  # All GPU node users can run gpu-arbiter (requires sudo)
  # =============================================================================
  security.sudo.extraRules = [
    {
      users = [
        "kosta"
        "kostagorod"
        "gonya"
      ];
      commands = [
        {
          command = "${pkgs.libvirt}/bin/virsh *";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/gpu-arbiter *";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

}

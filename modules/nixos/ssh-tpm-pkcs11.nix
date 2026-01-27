# SSH with TPM PKCS#11 authentication module
# Enables SSH key storage in TPM for hardware-backed security
# Reference: https://wiki.nixos.org/wiki/TPM
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.security.ssh-tpm;

  # Path to TPM2 PKCS#11 library on NixOS
  pkcs11Lib = "/run/current-system/sw/lib/libtpm2_pkcs11.so";

  # Helper script for TPM SSH key initialization
  tpm-ssh-init = pkgs.writeShellScriptBin "tpm-ssh-init" ''
    set -e

    echo "=== TPM SSH Key Initialization ==="
    echo ""
    echo "This script will create a new SSH key stored in your TPM."
    echo "You will need to set a PIN (userpin) and a Security Officer PIN (sopin)."
    echo "The SOPIN is used for PIN recovery/management."
    echo ""

    # Check TPM availability
    if [ ! -e /dev/tpmrm0 ]; then
      echo "Error: TPM device not found at /dev/tpmrm0"
      echo "Please ensure your TPM is enabled in BIOS/UEFI"
      exit 1
    fi

    # Check if user is in tss group
    if ! groups | grep -q tss; then
      echo "Error: You are not in the 'tss' group."
      echo "Please log out and log back in, or run: newgrp tss"
      exit 1
    fi

    # Initialize TPM store if needed
    if [ ! -d "$HOME/.tpm2_pkcs11" ]; then
      echo "Initializing TPM PKCS#11 store..."
      ${pkgs.tpm2-pkcs11}/bin/tpm2_ptool init
    fi

    # Create token with label 'ssh'
    echo ""
    echo "Creating SSH token in TPM..."
    echo "You will be prompted for a userpin and sopin."
    echo ""
    read -rsp "Enter userpin (your daily PIN): " userpin
    echo ""
    read -rsp "Confirm userpin: " userpin_confirm
    echo ""

    if [ "$userpin" != "$userpin_confirm" ]; then
      echo "Error: PINs do not match"
      exit 1
    fi

    read -rsp "Enter sopin (Security Officer PIN for recovery): " sopin
    echo ""
    read -rsp "Confirm sopin: " sopin_confirm
    echo ""

    if [ "$sopin" != "$sopin_confirm" ]; then
      echo "Error: SOPINs do not match"
      exit 1
    fi

    # Check if token already exists
    if ${pkgs.tpm2-pkcs11}/bin/tpm2_ptool listtokens 2>/dev/null | grep -q "label: ssh"; then
      echo "Token 'ssh' already exists. Skipping token creation."
    else
      ${pkgs.tpm2-pkcs11}/bin/tpm2_ptool addtoken \
        --pid=1 \
        --label=ssh \
        --userpin="$userpin" \
        --sopin="$sopin"
    fi

    # Generate ECC key
    echo ""
    echo "Generating ECC P-256 key in TPM..."
    ${pkgs.tpm2-pkcs11}/bin/tpm2_ptool addkey \
      --label=ssh \
      --userpin="$userpin" \
      --algorithm=ecc256

    echo ""
    echo "=== Success! ==="
    echo ""
    echo "Your SSH public key (add to authorized_keys):"
    echo ""
    ${pkgs.openssh}/bin/ssh-keygen -D ${pkcs11Lib}
    echo ""
    echo "To use this key, SSH config should have:"
    echo "  PKCS11Provider ${pkcs11Lib}"
    echo ""
    echo "Or use: ssh -I ${pkcs11Lib} user@host"
    echo ""
  '';

  # Helper script to show TPM SSH public key
  tpm-ssh-pubkey = pkgs.writeShellScriptBin "tpm-ssh-pubkey" ''
    ${pkgs.openssh}/bin/ssh-keygen -D ${pkcs11Lib}
  '';

  # Helper script for TPM token status
  tpm-ssh-status = pkgs.writeShellScriptBin "tpm-ssh-status" ''
    echo "=== TPM Status ==="
    if [ -e /dev/tpmrm0 ]; then
      echo "TPM device: /dev/tpmrm0 (available)"
    else
      echo "TPM device: not found"
      exit 1
    fi

    echo ""
    echo "=== TPM PKCS#11 Tokens ==="
    ${pkgs.tpm2-pkcs11}/bin/tpm2_ptool listtokens 2>/dev/null || echo "No tokens found"

    echo ""
    echo "=== SSH Public Keys from TPM ==="
    ${pkgs.openssh}/bin/ssh-keygen -D ${pkcs11Lib} 2>/dev/null || echo "No keys found"
  '';
in
{
  options.security.ssh-tpm = {
    enable = lib.mkEnableOption "SSH with TPM PKCS#11 key storage";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of users to grant TPM access (added to tss group)";
      example = [ "kosta" ];
    };

    sshConfigureAgent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Configure SSH agent to load TPM PKCS#11 provider";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable TPM2 support
    security.tpm2 = {
      enable = true;
      pkcs11.enable = true;           # Expose libtpm2_pkcs11.so
      tctiEnvironment.enable = true;  # Set TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI
    };

    # Add specified users to tss group for TPM access
    users.users = lib.genAttrs cfg.users (user: {
      extraGroups = [ "tss" ];
    });

    # Install TPM2 tools and utilities
    environment.systemPackages = [
      pkgs.tpm2-tools       # TPM2 CLI utilities
      pkgs.tpm2-pkcs11      # PKCS#11 library and tpm2_ptool
      pkgs.opensc           # pkcs11-tool for debugging

      # Helper scripts
      tpm-ssh-init
      tpm-ssh-pubkey
      tpm-ssh-status
    ];

    # Set environment variables for PKCS#11 library path
    environment.sessionVariables = {
      TPM2_PKCS11_LIBRARY = pkcs11Lib;
    };
  };
}

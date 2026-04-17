# nix-config

My NixOS configuration. Two machines, one repo, fully declarative.

**rocinante** is my daily driver -- a ThinkPad running Plasma 6 and COSMIC side by side, loaded with AI coding tools, hardware security (TPM-backed SSH keys, YubiKey, fingerprint), and a Tailscale mesh connecting everything together. Power management is tuned per-profile with TLP, battery health thresholds, and runtime PM tweaks for the touchpad.

**gpu-node-1** is a headless GPU compute node running Kubernetes (K3s) with NVIDIA passthrough and a GPU arbiter that can hot-swap between AI workloads and VFIO VMs.

Both machines are built from the same flake, sharing modules for things like Tailscale split-DNS, secrets management (agenix), and a growing collection of AI tool integrations -- Claude Code, OpenCode, Gemini CLI, Kimi, Droids, Abacus.AI DeepAgent, and a self-hosted Mem0 memory layer backed by Qdrant.

User environment is managed with home-manager: editors (Helix, VSCode, Zed), shell (Bash + Starship + Direnv), git with OAuth credentials, and the usual desktop apps.

Custom overlays patch Spotify with SpotX and add sensitive clipboard support to wl-clipboard for password manager integration.

## Deploy

```sh
sudo nixos-rebuild switch --flake .#rocinante
```

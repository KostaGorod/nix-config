# COSMIC Desktop Environment

COSMIC has been added as an additional desktop environment option alongside Plasma 6.

## How to Launch COSMIC

1. **Rebuild your NixOS configuration:**
   ```bash
   sudo nixos-rebuild switch
   ```

2. **At the COSMIC greeter:**
   - Click on the desktop session icon (usually shows "Plasma (Wayland)" by default)
   - Select "COSMIC" from the dropdown menu
   - Enter your password and login

## What's Included

The COSMIC module includes:
- **Core Components**: cosmic-comp (compositor), cosmic-panel, cosmic-applets, cosmic-session
- **Applications**: cosmic-files, cosmic-term, cosmic-settings, cosmic-store
- **Desktop Integration**: xdg-desktop-portal-cosmic, cosmic-icons
- **Performance Optimizations**: System76 scheduler enabled
- **Clipboard Support**: COSMIC data control enabled

## Switching Between Desktop Environments

You can switch between Plasma 6 and COSMIC at any time:
- **Plasma 6 (Default)**: Select "Plasma (Wayland)" at login
- **COSMIC**: Select "COSMIC" at login

Your user files, settings, and applications are shared between both desktop environments.

## Performance Notes

COSMIC includes the System76 scheduler for better performance. If you experience any issues, disable it in `modules/services/workstation.nix`:
```nix
# services.system76-scheduler.enable = true;
```

## Troubleshooting

If COSMIC doesn't appear in the session list:
1. Ensure you've rebuilt with `sudo nixos-rebuild switch`
2. Check that greetd is running: `systemctl status greetd`
3. Verify COSMIC packages are installed: `nix-store -q /run/current-system/sw | grep cosmic`

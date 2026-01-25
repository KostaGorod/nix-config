# Soteria Bug Report: XDG_SESSION_ID not available in systemd user services on COSMIC DE

## Summary

Soteria v0.3.0 fails to start on COSMIC Desktop Environment when launched as a systemd user service because `XDG_SESSION_ID` is not propagated to the systemd user environment.

## Environment

- **OS**: NixOS 24.11
- **Desktop Environment**: COSMIC (System76)
- **Display Server**: Wayland
- **Soteria Version**: 0.3.0
- **Session Manager**: greetd

## Error Message

```
Error: Could not get XDG session id, make sure that it is set and try again.
Caused by:
    environment variable not found
Location:
    src/main.rs:82:18
```

## Root Cause Analysis

### The Problem

COSMIC DE does not propagate `XDG_SESSION_ID` to the systemd user service manager environment. This is a common issue with newer Wayland compositors that don't integrate with systemd the same way GNOME or KDE do.

### Evidence

```bash
# XDG_SESSION_ID exists in shell environment
$ echo $XDG_SESSION_ID
3

# But NOT in systemd user environment
$ systemctl --user show-environment | grep XDG_SESSION_ID
# (empty - not present)

# Session is valid and active
$ loginctl show-session 3
Id=3
User=1000
Name=kosta
Desktop=COSMIC
Type=wayland
Class=user
Active=yes
State=active
```

### Why This Happens

1. `greetd` creates the session and sets `XDG_SESSION_ID` in PAM
2. COSMIC compositor starts but doesn't run `dbus-update-activation-environment --systemd XDG_SESSION_ID`
3. Systemd user services don't inherit the shell environment
4. Soteria requires `XDG_SESSION_ID` at `src/main.rs:82` via `std::env::var("XDG_SESSION_ID")?`

## Affected Desktop Environments

- COSMIC (System76)
- Potentially other Wayland compositors that don't use systemd integration
- Any DE using greetd without explicit environment propagation

## Workaround

### Option 1: Wrapper Script (Current Solution)

Fetch `XDG_SESSION_ID` from `loginctl` at runtime:

```bash
#!/bin/bash
if [ -z "$XDG_SESSION_ID" ]; then
  export XDG_SESSION_ID=$(loginctl list-sessions --no-legend | awk -v user="$USER" '$3 == user {print $1; exit}')
fi
exec soteria
```

### Option 2: Systemd Service Override

Add to the service unit:

```ini
[Service]
ExecStartPre=/bin/sh -c 'systemctl --user set-environment XDG_SESSION_ID=$(loginctl list-sessions --no-legend | awk -v user="$USER" "$3 == user {print $1; exit}")'
```

## Suggested Fix for Soteria

### Option A: Graceful Fallback (Recommended)

Modify `src/main.rs` to fallback to loginctl when env var is missing:

```rust
fn get_session_id() -> Result<String> {
    // Try environment first
    if let Ok(id) = std::env::var("XDG_SESSION_ID") {
        return Ok(id);
    }
    
    // Fallback: query loginctl
    let output = std::process::Command::new("loginctl")
        .args(["list-sessions", "--no-legend"])
        .output()?;
    
    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 3 {
            let session_user = parts[2];
            if let Ok(current_user) = std::env::var("USER") {
                if session_user == current_user {
                    return Ok(parts[0].to_string());
                }
            }
        }
    }
    
    Err(anyhow!("Could not determine XDG_SESSION_ID from environment or loginctl"))
}
```

### Option B: Document the Requirement

Add to README.md:

```markdown
## COSMIC / Wayland Compositors

If using COSMIC DE or other compositors that don't propagate XDG_SESSION_ID to systemd,
ensure your compositor startup runs:

    dbus-update-activation-environment --systemd XDG_SESSION_ID

Or use the wrapper script approach documented in the wiki.
```

### Option C: Make XDG_SESSION_ID Optional

If `XDG_SESSION_ID` is only used for polkit agent registration scope, consider making it optional and defaulting to a reasonable value.

## Related Issues

- [COSMIC Desktop Environment](https://github.com/pop-os/cosmic-epoch) - No native polkit agent yet
- Similar issues reported for Hyprland, Sway, and other wlroots-based compositors

## Test Case

```bash
# 1. Start COSMIC DE via greetd
# 2. Verify session exists
loginctl list-sessions

# 3. Check systemd user env (should be missing XDG_SESSION_ID)
systemctl --user show-environment | grep XDG_SESSION_ID

# 4. Start soteria
soteria
# ERROR: Could not get XDG session id

# 5. With workaround
export XDG_SESSION_ID=$(loginctl list-sessions --no-legend | awk -v user="$USER" '$3 == user {print $1; exit}')
soteria
# SUCCESS: Registering authentication agent...
```

## References

- Soteria source: https://github.com/ImVaskel/soteria
- COSMIC DE: https://github.com/pop-os/cosmic-epoch
- systemd user environment: https://wiki.archlinux.org/title/Systemd/User#Environment_variables

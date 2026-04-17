# COSMIC Blank Screen (Background + Cursor) Bug Report

## Title
COSMIC shows background + mouse cursor but no login UI / unusable session (cosmic-comp DRM master failures).

## Severity
High (blocks login / interactive use).

## Environment
- Host: `rocinante`
- OS: NixOS 25.11 (Xantusia)
- Display stack:
  - `services.greetd.enable = true` (via COSMIC greeter module)
  - `services.displayManager.cosmic-greeter.enable = true`
- COSMIC packages observed:
  - `cosmic-greeter 1.0.0`
  - `cosmic-session 1.0.0`
  - `cosmic-comp 1.0.0`
- GPU: Intel i915 (TGL) (inferred from kernel logs)

## Symptom
On the graphical VT, only a background image and a mouse cursor appear; the expected login UI does not render or the session is otherwise unusable.

## Expected
COSMIC greeter shows a functional login UI and/or COSMIC user session renders normally.

## Actual
The compositor stack starts but fails to properly take control of KMS, leaving the screen effectively blank except for background/cursor.

## Key Observations

### Greeter / session manager
- `greetd` is the display manager (systemd service `greetd.service`).
- COSMIC greeter is started by greetd using `cosmic-greeter-start`.
- A session bus is explicitly started for the greeter using `dbus-run-session`.

Example generated greetd config snippet:

```toml
[default_session]
command = ".../dbus-run-session -- .../env XCURSOR_THEME=\"${XCURSOR_THEME:-Pop}\" .../cosmic-greeter-start"
user = "cosmic-greeter"
```

### DRM/KMS failure signature
The most correlated failure is that `cosmic-comp` cannot become DRM master and later errors on commits:

- `Unable to become drm master, assuming unprivileged mode`
- `Unable to clear state: DRM access error: Failed to commit on clear_state ... (Permission denied (os error 13))`

This suggests the compositor cannot reliably acquire KMS control, which can yield a “background + cursor” presentation without a functional UI.

### Session activity / VT switching interaction
When working from another VT (e.g. `tty2` for debugging), `loginctl` shows the graphical COSMIC session on `tty1` can become inactive. KMS control can be revoked by logind when a session is not active.

Recovery command tested:

```sh
loginctl activate 3
```

This forces the graphical session (example session id `3`) to become active again.

## Debug Process Flow (What Was Done)
1) Identify which display manager is running
   - `systemctl status greetd.service`
2) Identify what greetd launches
   - Read greetd’s generated `greetd.toml` from `/nix/store/...-greetd.toml`
3) Confirm COSMIC processes are alive
   - `pgrep -a greetd cosmic-greeter cosmic-comp cosmic-session`
4) Inspect the journal for greeter/compositor failures
   - `journalctl -b | rg -i 'cosmic-greeter|cosmic-comp|drm master|Permission denied'`
5) Check logind session state / which VT is active
   - `loginctl list-sessions`
   - `loginctl session-status <id>`
6) Check DRM node permissions and which process holds it
   - `ls -l /dev/dri`
   - `getfacl /dev/dri/card1`
   - `lsof /dev/dri/card1`

## Mitigations / Fixes Attempted

### 1) Ensure greeter has a session bus
Problem: COSMIC greeter logs repeated D-Bus watcher failures in the “blank UI” condition.

Fix: wrap `cosmic-greeter-start` with `dbus-run-session` in greetd’s `default_session.command`.

Location: `de/cosmic.nix`

### 2) Reduce PAM env noise
Problem: `pam_env` warns that expandable variables must be wrapped in `${...}`.

Fix: set `SSH_AUTH_SOCK` as `"\${XDG_RUNTIME_DIR}/ssh-agent"`.

Location: `modules/nixos/ssh-tpm-pkcs11.nix`

### 3) Improve DRM seat handling (next step)
Hypothesis: `cosmic-comp` needs a more reliable seat backend.

Planned fix: enable `services.seatd.enable = true`, add relevant users to `seat` group, and prefer `LIBSEAT_BACKEND=seatd`.

Location: `de/cosmic.nix`

## Afterthoughts
- The “background + cursor” failure mode is misleading because it looks like graphics is working, but the compositor’s ability to control KMS is degraded.
- The log line `Unable to become drm master` is a strong indicator that the session will not render correctly. It should be treated as a hard failure for a VT compositor.
- Debugging from a different VT can make the graphical session inactive. If the bug is sensitive to session activation, it’s useful to explicitly `loginctl activate <session>` while testing.
- Upstream/NixOS module improvement idea: COSMIC greeter module could optionally enable seatd and/or force libseat backend selection when running on TTY KMS.

# NixOS Security Audit Report

**Date:** 2026-01-19
**Tool:** vulnix 1.12.2
**System:** rocinante
**Branch:** refactor/flake-parts-modular-structure

## Executive Summary

Vulnix scan identified **110 derivations with active advisories**. After analysis:
- **~70 are false positives** (Haskell package name collisions)
- **~10 already patched** in current system
- **~15 awaiting upstream fixes**
- **~15 actionable items** requiring attention

### Current System Status

| Component | Installed | Required | Status |
|-----------|-----------|----------|--------|
| polkit | 126 | 122+ | PATCHED |
| glibc | 2.40 | 2.40+ | PATCHED |
| perl | 5.40.0 | 5.40.2+ | NEEDS UPDATE |
| nix | 2.34pre | 2.20.5+ | OK |

---

## False Positives (Name Collisions)

These Haskell packages match CVEs for unrelated products:

| Package | Matched Product | Actual Package |
|---------|-----------------|----------------|
| network-3.2.8.0 | Fidelis Network | Haskell network library |
| vault-0.3.1.5 | HashiCorp Vault | Haskell vault (type-safe keys) |
| warp-3.4.9 | Cloudflare Warp | Haskell WAI web server |
| safe-0.3.21 | F-Secure SAFE | Haskell safe partial functions |
| curl-0.4.46 | libcurl | Haskell curl bindings |
| async-2.2.5 | JS async library | Haskell async concurrency |
| yaml-0.11.11.2 | Go yaml.v2 | Haskell YAML parser |
| websockets-0.13.0.0 | Various | Haskell WebSocket library |
| dbus-0.9.7 | D-Bus daemon | Haskell D-Bus bindings |
| systemd-2.4.0 | systemd daemon | Haskell systemd bindings |
| zlib-0.7.1.1 | zlib C library | Haskell zlib bindings |
| hedgehog-1.5 | Hedgehog CMS | Haskell property testing |
| idna-0.5.0 | Python IDNA | Haskell IDNA |
| word-wrap-0.5 | npm word-wrap | Haskell word-wrap |
| tap-1.0.1 | Jenkins TAP plugin | Haskell TAP |
| stringbuilder-0.5.1 | Node.js package | Haskell stringbuilder |
| xunit-2.9.2 | .NET xUnit | NixOS test framework |
| Diff-1.0.2 | Various | Haskell Diff |
| git-2.51/2.52 | Jenkins Git plugin | Git SCM |
| mercurial-7.1 | Jenkins Mercurial plugin | Mercurial SCM |
| snappy-1.2.2 | PHP Snappy | Google Snappy compression |
| memcached-1.6.39 | PHP-Memcached | Memcached server |

---

## Real Vulnerabilities

### Critical (CVSSv3 >= 8.0)

| Package | CVE | Score | Description | Status |
|---------|-----|-------|-------------|--------|
| python-2.7.18.12 | Multiple | 9.8 | EOL, multiple critical CVEs | REMOVE IF POSSIBLE |
| orc-0.4.41 | CVE-2025-47436 | 9.8 | Heap overflow in LZO decompression | WAIT FOR UPDATE |
| gpsd-3.27 | CVE-2025-67268 | 9.8 | Critical RCE | WAIT FOR UPDATE |
| freerdp-3.17.2 | CVE-2025-68118 | 9.1 | RCE vulnerability | WAIT FOR UPDATE |
| perl-5.38.2/5.40.0 | CVE-2024-56406 | 8.4 | Heap buffer overflow in tr// | UPDATE TO 5.40.2+ |
| glibc-2.39-52 | CVE-2024-33599 | 8.1 | nscd stack overflow | PATCHED (2.40) |
| ffmpeg-6.1.3 | CVE-2023-49502 | 8.8 | Buffer overflow | UPDATE TO 7.x/8.x |

### Medium (CVSSv3 5.0-7.9)

| Package | CVE | Score | Description | Status |
|---------|-----|-------|-------------|--------|
| polkit-1 | CVE-2021-4034 | 7.8 | PwnKit LPE | PATCHED (126) |
| gnupg-2.4.8 | CVE-2025-68973 | 7.8 | Local privilege issue | WAIT FOR UPDATE |
| openexr-3.3.5 | Multiple | 7.8 | Heap overflows | WAIT FOR UPDATE |
| fontforge-20251009 | Multiple | 7.8 | Buffer overflows | WAIT FOR UPDATE |
| libsndfile-1.2.2 | CVE-2025-52194 | 7.5 | Buffer overflow | WAIT FOR UPDATE |
| fluidsynth-2.5.x | CVE-2025-68617 | 7.0 | Memory corruption | WAIT FOR UPDATE |
| cups-2.4.14 | CVE-2022-26691 | 6.7 | Auth bypass | UPDATE TO 2.4.16 |
| nix-0.30.1 | CVE-2024-27297 | 6.3 | Sandbox bypass | OK (system nix newer) |
| discord-0.0.117 | CVE-2024-23739 | 9.8 | RCE (macOS only) | N/A ON LINUX |

### Low Priority

| Package | CVE | Score | Notes |
|---------|-----|-------|-------|
| gcc-13/14/15 | CVE-2023-4039 | 4.8 | ARM64 only, mitigation weakness |
| binutils-2.41/2.44 | Multiple | 3-5 | DoS only, crafted input required |
| busybox-1.36.1 | Multiple | 3-6 | Limited attack surface |
| avahi-0.8 | Multiple | 5-7 | Local network only |
| imagemagick-7.1.2-x | Multiple | 4-5 | DoS vulnerabilities |

---

## Attack Vector Analysis

### Open Vectors

| Vector | Risk | Affected | Mitigation |
|--------|------|----------|------------|
| Malicious file processing | MEDIUM | ffmpeg, imagemagick, fontforge, openexr | Don't process untrusted media |
| Network services | MEDIUM | cups, avahi, gpsd, freerdp | Firewall, disable if unused |
| Python 2.7 scripts | HIGH | python-2.7.18.12 | Remove Python 2 dependency |
| Build-time | LOW | gcc, binutils, ninja | Development only |

### Closed Vectors

- **PwnKit (polkit)**: Patched in polkit 126
- **glibc nscd**: Patched in glibc 2.40
- **Discord RCE**: macOS-specific
- **Nix sandbox bypass**: System nix is newer than 0.30.1

---

## Remediation Plan

### Immediate Actions

- [ ] Run `nix flake update` to get latest security patches
- [ ] Run `sudo nixos-rebuild switch` after update
- [ ] Verify perl updates to 5.40.2+

### Short-term Actions

- [ ] Investigate Python 2.7 dependency chain: `nix why-depends /run/current-system nixpkgs#python27`
- [x] Disable `nscd` (not needed on this host) in `hosts/rocinante/configuration.nix`
- [ ] Review CUPS exposure: restrict to localhost if only local printing
- [x] Disable Avahi (mDNS) in `hosts/rocinante/configuration.nix`

### Applied mitigations (before/after)

- **Before (as-scanned)**: `services.avahi.enable = true` (mDNS enabled), `services.nscd.enable = true` (nscd enabled)
- **After (committed config)**: `services.avahi.enable = false` and `services.nscd.enable = false`
- **Why**: Avahi broadens LAN attack surface; nscd is low-value on desktops and is a common “nscd-only” CVE target.
- **Impact**: Disabling Avahi may break auto-discovery of printers via mDNS/Bonjour. Printing itself remains enabled; configure printers explicitly if needed.

### pkexec (polkit) note

- `pkexec` is installed as a setuid wrapper on NixOS (`/run/wrappers/bin/pkexec`). This is expected when `security.polkit.enable = true`.
- The historical risk here is PwnKit (`CVE-2021-4034`). On this host we observed `polkit` at `126`, which is past the vulnerable versions.
- Keep `polkit` updated and avoid downgrades/pinning to older releases.

### Long-term Actions

- [ ] Create vulnix whitelist for false positives (see below)
- [ ] Set up automated vulnix scanning in CI
- [ ] Monitor upstream for fixes to orc, gpsd, freerdp, gnupg, openexr, fontforge

---

## Vulnix Whitelist

Create `~/.config/vulnix/whitelist.toml`:

```toml
# Haskell packages - name collisions with unrelated products

[network]
cve = ["CVE-2021-35047", "CVE-2021-35048", "CVE-2021-35049", "CVE-2022-24388", "CVE-2022-24389", "CVE-2022-24390", "CVE-2022-24391", "CVE-2022-24392", "CVE-2022-24393", "CVE-2022-24394", "CVE-2021-35050", "CVE-2022-0486", "CVE-2022-0997"]
comment = "Haskell network package, not Fidelis Network"

[vault]
cve = ["CVE-2024-2048", "CVE-2021-27400", "CVE-2023-6337", "CVE-2025-6037", "CVE-2023-0620", "CVE-2023-0665", "CVE-2025-6014", "CVE-2024-8365", "CVE-2021-3024", "CVE-2021-38554", "CVE-2022-41316", "CVE-2023-25000", "CVE-2025-4166", "CVE-2023-24999", "CVE-2023-2121", "CVE-2025-6011", "CVE-2021-41802"]
comment = "Haskell vault package, not HashiCorp Vault"

[warp]
cve = ["CVE-2022-4428", "CVE-2022-2225", "CVE-2023-2754", "CVE-2023-1862", "CVE-2025-0651", "CVE-2023-0652", "CVE-2023-1412", "CVE-2022-3320", "CVE-2022-3512", "CVE-2022-2145", "CVE-2022-4457", "CVE-2023-0238", "CVE-2023-0654"]
comment = "Haskell warp web server, not Cloudflare Warp"

[safe]
cve = ["CVE-2022-38164", "CVE-2022-47524", "CVE-2021-40835", "CVE-2021-40834", "CVE-2021-44751", "CVE-2022-28868", "CVE-2022-28869", "CVE-2022-28870", "CVE-2022-28872", "CVE-2022-28873", "CVE-2021-33594", "CVE-2021-33595", "CVE-2021-33596", "CVE-2022-38163"]
comment = "Haskell safe package, not F-Secure SAFE"

[systemd]
cve = ["CVE-2023-26604", "CVE-2021-33910", "CVE-2022-3821", "CVE-2025-4598"]
comment = "Haskell systemd binding, not systemd daemon"

[curl]
cve = ["CVE-2022-32221", "CVE-2022-27781", "CVE-2022-27782", "CVE-2023-28319", "CVE-2022-27776", "CVE-2022-32206", "CVE-2022-43552", "CVE-2023-28320", "CVE-2023-28321", "CVE-2022-35252", "CVE-2023-28322"]
comment = "Haskell curl binding, not libcurl"

[async]
cve = ["CVE-2021-43138"]
comment = "Haskell async package, not JS async library"

[yaml]
cve = ["CVE-2022-3064", "CVE-2021-4235"]
comment = "Haskell yaml package, not Go yaml.v2"

[websockets]
cve = ["CVE-2021-33880"]
comment = "Haskell websockets package"

[dbus]
cve = ["CVE-2022-42010", "CVE-2022-42011", "CVE-2022-42012"]
comment = "Haskell dbus binding, not dbus daemon"

[git]
cve = ["CVE-2022-36882", "CVE-2022-30947", "CVE-2022-36883", "CVE-2022-38663", "CVE-2021-21684", "CVE-2022-36884"]
comment = "Jenkins Git plugin CVEs, not git SCM"

[mercurial]
cve = ["CVE-2022-43410"]
comment = "Jenkins Mercurial plugin CVE"

[snappy]
cve = ["CVE-2023-28115", "CVE-2023-41330"]
comment = "PHP Snappy CVEs, not Google Snappy compression"

[memcached]
cve = ["CVE-2022-26635"]
comment = "PHP-Memcached CVE, disputed for memcached server"

[discord]
cve = ["CVE-2024-23739"]
comment = "macOS only vulnerability, not applicable on Linux"
```

---

## References

- [PwnKit CVE-2021-4034](https://blog.qualys.com/vulnerabilities-threat-research/2022/01/25/pwnkit-local-privilege-escalation-vulnerability-discovered-in-polkits-pkexec-cve-2021-4034)
- [glibc nscd CVE-2024-33599](https://nvd.nist.gov/vuln/detail/cve-2024-33599)
- [Perl CVE-2024-56406](https://securityonline.info/cve-2024-56406-heap-overflow-vulnerability-in-perl-threatens-denial-of-service-and-potential-code-execution/)
- [GCC ARM64 CVE-2023-4039](https://rtx.meta.security/mitigation/2023/09/12/CVE-2023-4039.html)
- [Nix CVE-2024-27297](https://securityvulnerability.io/vulnerability/CVE-2024-27297)
- [Apache ORC CVE-2025-47436](https://orc.apache.org/security/CVE-2025-47436/)
- [Discord CVE-2024-23739](https://www.cve.news/cve-2024-23739/)

---

## Scan Command

```bash
nix shell nixpkgs#vulnix -c vulnix --system --verbose
```

## Next Scan

Schedule follow-up scan after `nix flake update` to verify remediation.

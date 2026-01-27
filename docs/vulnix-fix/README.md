# Vulnix Vendor-Aware Matching Fix

This directory contains materials for reporting and fixing the false positive issue in vulnix.

## The Problem

Vulnix ignores the `vendor` field from CPE (Common Platform Enumeration) entries when matching Nix packages to CVEs. This causes widespread false positives when package names collide across different ecosystems.

### Example

The Haskell `network` library (a TCP/UDP socket library) matches CVEs for:
- **Fidelis Network** (enterprise security product) - 13 critical CVEs
- **Network Solutions** (domain registrar) - various CVEs

These are completely unrelated products that happen to share the name "network".

### Root Cause

In `src/vulnix/vulnerability.py`:

```python
# Currently, vendor strings are ignored completely while matching.
# This may change in a future version.
```

The CPE format is: `cpe:2.3:a:<vendor>:<product>:<version>:...`

Vulnix only uses `<product>`, ignoring `<vendor>`.

## Impact

In our audit of a NixOS system:
- **110 derivations flagged** with CVE advisories
- **~70 were false positives** (64%) due to this issue
- Primarily affects **Haskell packages** with common names

### Most Affected Packages

| Package | False Vendor | CVEs |
|---------|-------------|------|
| network | Fidelis | 13 |
| vault | HashiCorp | 17 |
| warp | Cloudflare | 13 |
| safe | F-Secure | 14 |
| curl | Haxx | 11 |
| git | Jenkins | 6 |

## Files

- `vulnix-bug-report.md` - Full bug report for GitHub issue
- `vendor_aware_matching.patch` - Proof of concept patch
- `ecosystem_detector.py` - Python module for ecosystem detection

## Proposed Fix

1. **Store vendor from CPE** - Parse and store vendor field
2. **Detect ecosystem from derivation** - Infer vendor from drv path/inputs
3. **Prefer vendor+product matches** - When ecosystem is known
4. **Filter commercial vendors** - For ecosystem packages

### Ecosystem Detection Heuristics

```python
# From derivation path patterns:
'haskellPackages' → ecosystem='hackage'
'python3Packages' → ecosystem='pypi'
'nodePackages'    → ecosystem='npm'
'rustPackages'    → ecosystem='crates.io'

# From build inputs:
ghc dependency    → ecosystem='hackage'
python dependency → ecosystem='pypi'
```

## Testing

```bash
# Run ecosystem detector demo
python ecosystem_detector.py

# Test on actual derivation
python ecosystem_detector.py /nix/store/xxx-network-3.2.8.0.drv
```

## Related Issues

- [#62](https://github.com/nix-community/vulnix/issues/62) - CPE pattern blacklisting
- [#94](https://github.com/nix-community/vulnix/issues/94) - Third-party database integration
- [#81](https://github.com/nix-community/vulnix/issues/81) - Frequent false positives
- [#91](https://github.com/nix-community/vulnix/issues/91) - Bolt false positive

## Next Steps

1. File GitHub issue with bug report
2. Discuss approach with maintainers
3. Submit PR with fix
4. Consider proposing `meta.cpe` for nixpkgs

## References

- [CPE Specification](https://nvd.nist.gov/products/cpe)
- [PURL Spec](https://github.com/package-url/purl-spec)
- [Grype's approach](https://anchore.com/blog/false-positives-and-false-negatives-in-vulnerability-scanning/) - Moved away from CPE-only matching
- [Dependency-Track CPE issues](https://github.com/DependencyTrack/dependency-track/issues/3063)

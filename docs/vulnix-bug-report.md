# Vulnix Bug Report: Vendor-Ignorant Matching Causes Mass False Positives

**Repository:** https://github.com/nix-community/vulnix
**Related Issues:** #62, #94, #81, #91

## Summary

Vulnix ignores the `vendor` field from CPE entries when matching packages to CVEs, causing widespread false positives when package names collide across different ecosystems. This is particularly severe for Haskell packages in NixOS, where common names like `network`, `vault`, `warp`, and `safe` match CVEs for completely unrelated commercial products.

## Severity

**High** - In our scan, ~70 of 110 flagged derivations (64%) were false positives due to this issue, making the tool's output nearly unusable without extensive manual whitelisting.

## Root Cause

In `src/vulnix/vulnerability.py`, line ~XX contains:

```python
# Currently, vendor strings are ignored completely while matching.
# This may change in a future version.
```

The matching flow:
1. `derivation.py` extracts package name (e.g., `network-3.2.8.0` → `network`)
2. `nvd.py` queries `by_product["network"]` - no vendor filter
3. Returns ALL CVEs where product="network", regardless of vendor

## Reproduction

```bash
nix shell nixpkgs#vulnix -c vulnix --system 2>&1 | grep -E "^(network|vault|warp|safe)-"
```

Output shows Haskell packages matched to:
- `network` → Fidelis Network (enterprise security product)
- `vault` → HashiCorp Vault (secrets management)
- `warp` → Cloudflare Warp (VPN client)
- `safe` → F-Secure SAFE (antivirus)

## Affected Packages (Partial List)

| Nix Package | False Vendor Match | CVE Count |
|-------------|-------------------|-----------|
| network-3.2.8.0 | Fidelis Cybersecurity | 13 |
| vault-0.3.1.5 | HashiCorp | 17 |
| warp-3.4.9 | Cloudflare | 13 |
| safe-0.3.21 | F-Secure | 14 |
| curl-0.4.46 | Haxx (libcurl) | 11 |
| async-2.2.5 | Caolan (npm) | 1 |
| yaml-0.11.11.2 | Go yaml.v2 | 2 |
| systemd-2.4.0 | systemd project | 4 |
| dbus-0.9.7 | freedesktop.org | 3 |
| git-2.51.2 | Jenkins Git plugin | 6 |
| memcached-1.6.39 | PHP-Memcached | 1 |
| snappy-1.2.2 | PHP Snappy | 2 |

## Proposed Solutions

### Solution 1: Vendor-Aware Matching (Recommended)

Modify the matching algorithm to consider vendor when available:

```python
# In nvd.py - new index
self.by_vendor_product = OOBTree()  # Maps (vendor, product) -> [vulns]

# In vulnerability.py - store vendor
class Node:
    def __init__(self):
        self.vendor = None  # NEW
        self.product = None
        self.version = None

# In derivation.py - ecosystem hints
def infer_vendor(self, pname, drv_path):
    """Infer vendor/ecosystem from derivation metadata."""
    # Check if it's a Haskell package
    if "haskellPackages" in drv_path or self.has_ghc_dependency():
        return "haskell"  # or "hackage"
    # Check for other ecosystems...
    return None

# In matching - prefer vendor match
def affected(self, pname, version, vendor_hint=None):
    if vendor_hint:
        # Try exact vendor:product match first
        key = (vendor_hint, pname)
        if key in self.by_vendor_product:
            return self._match_vulns(self.by_vendor_product[key], version)
    # Fall back to product-only (current behavior)
    return self._match_vulns(self.by_product.get(pname, []), version)
```

### Solution 2: Ecosystem-Based Filtering

Add ecosystem metadata to nixpkgs and use it for filtering:

```nix
# In nixpkgs package definition
meta = {
  cpe = {
    vendor = "hackage";  # or inferred from haskellPackages
    product = "network";
  };
};
```

### Solution 3: Negative Vendor Matching

Allow whitelists to specify "not this vendor":

```toml
[network]
vendor_exclude = ["fidelis", "fidelis_cybersecurity"]
comment = "Haskell network package, not Fidelis Network"
```

### Solution 4: PURL Integration (per Issue #94)

Use Package URL (purl) format which includes ecosystem:

```
pkg:hackage/network@3.2.8.0   # Haskell
pkg:npm/async@2.2.5           # Node.js
pkg:cargo/warp@3.4.9          # Rust (different warp!)
```

## Implementation Approach

### Phase 1: Quick Win
Add vendor to the index and matching logic. Default to current behavior when no vendor hint available.

### Phase 2: Ecosystem Detection
Infer ecosystem from:
- Derivation path (`haskellPackages.network` → vendor=hackage)
- Build inputs (ghc dependency → Haskell)
- Source URL patterns (hackage.haskell.org → Haskell)

### Phase 3: Nixpkgs Integration
Propose `meta.cpe` attribute for explicit vendor/product mapping in nixpkgs.

## Workaround

Create extensive whitelists (see attached), but this is unsustainable as:
1. New Haskell packages need manual addition
2. CVE lists change, requiring whitelist updates
3. Doesn't scale across the ecosystem

## Test Case

```python
def test_vendor_aware_matching():
    """Haskell 'network' should not match Fidelis 'network' CVEs."""
    nvd = NVD()

    # Load CVE-2021-35047 (Fidelis Network)
    # CPE: cpe:2.3:a:fidelis:network:*:*:*:*:*:*:*:*

    # Should NOT match Haskell network package
    vulns = nvd.affected("network", "3.2.8.0", vendor_hint="hackage")
    assert len(vulns) == 0, "Haskell network matched Fidelis CVE"

    # Should match actual Fidelis product
    vulns = nvd.affected("network", "9.0", vendor_hint="fidelis")
    assert any(v.id == "CVE-2021-35047" for v in vulns)
```

## References

- CPE Specification: https://nvd.nist.gov/products/cpe
- PURL Spec: https://github.com/package-url/purl-spec
- Grype's approach: https://github.com/anchore/grype (moved away from CPE-only matching)
- Related vulnix issues: #62, #94, #81

## Environment

- vulnix 1.12.2
- NixOS unstable (2026-01)
- NVD data from fkie-cad/nvd-json-data-feeds

---

*This report was generated during a security audit of a NixOS system where 64% of flagged vulnerabilities were false positives due to this issue.*

#!/usr/bin/env python3
"""
Ecosystem Detector for Nix Derivations

This module demonstrates how to detect the ecosystem/vendor of a Nix package
from its derivation path and metadata. This information can be used to filter
CVE matches and reduce false positives in vulnerability scanning.

Usage:
    python ecosystem_detector.py /nix/store/xxx-network-3.2.8.0.drv
"""

import json
import re
import sys
from pathlib import Path
from typing import Optional, Dict, Set

# Mapping of path patterns to ecosystems
ECOSYSTEM_PATTERNS = {
    'hackage': [
        r'haskellPackages',
        r'haskell\.packages',
        r'ghc\d+',
        r'cabal-install',
        r'\.cabal$',
    ],
    'pypi': [
        r'python\d*Packages',
        r'python\d+-',
        r'pip-',
        r'\.whl$',
    ],
    'npm': [
        r'nodePackages',
        r'node-',
        r'npm-',
        r'node_modules',
    ],
    'crates.io': [
        r'rustPackages',
        r'cargo-',
        r'crates-io',
        r'\.crate$',
    ],
    'go': [
        r'buildGoModule',
        r'go-modules',
        r'goPackages',
    ],
    'cpan': [
        r'perlPackages',
        r'perl\d+-',
    ],
    'rubygems': [
        r'rubyPackages',
        r'bundlerEnv',
        r'\.gem$',
    ],
    'maven': [
        r'\.jar$',
        r'maven-',
    ],
    'nuget': [
        r'nuget-',
        r'dotnet-',
    ],
}

# Known vendor mappings for common false positives
# Maps (ecosystem, product) -> should NOT match these NVD vendors
FALSE_POSITIVE_VENDORS: Dict[tuple, Set[str]] = {
    ('hackage', 'network'): {'fidelis', 'fidelis_cybersecurity'},
    ('hackage', 'vault'): {'hashicorp'},
    ('hackage', 'warp'): {'cloudflare'},
    ('hackage', 'safe'): {'f-secure', 'f_secure'},
    ('hackage', 'curl'): {'haxx'},
    ('hackage', 'async'): {'caolan'},
    ('hackage', 'yaml'): {'yaml_project'},
    ('hackage', 'systemd'): {'systemd_project'},
    ('hackage', 'dbus'): {'freedesktop'},
    ('hackage', 'websockets'): {'websockets_project'},
    ('hackage', 'hedgehog'): {'hedgehog'},
    ('hackage', 'idna'): {'idna_project'},
    # Add more as discovered...
}

# Build inputs that indicate ecosystem
BUILD_INPUT_INDICATORS = {
    'hackage': ['ghc', 'cabal-install', 'haskell-language-server'],
    'pypi': ['python3', 'pip', 'setuptools'],
    'npm': ['nodejs', 'npm'],
    'crates.io': ['rustc', 'cargo'],
    'go': ['go'],
}


def detect_ecosystem(drv_path: str, drv_content: Optional[dict] = None) -> Optional[str]:
    """
    Detect the ecosystem of a Nix derivation.

    Args:
        drv_path: Path to the .drv file or store path
        drv_content: Optional parsed derivation content

    Returns:
        Ecosystem identifier (e.g., 'hackage', 'pypi') or None if unknown
    """
    path_str = str(drv_path)

    # Check path patterns
    for ecosystem, patterns in ECOSYSTEM_PATTERNS.items():
        for pattern in patterns:
            if re.search(pattern, path_str, re.IGNORECASE):
                return ecosystem

    # Check derivation content if available
    if drv_content:
        # Check builder
        builder = drv_content.get('builder', '')
        if 'ghc' in builder:
            return 'hackage'
        if 'python' in builder:
            return 'pypi'

        # Check build inputs
        inputs = drv_content.get('inputDrvs', {})
        input_names = ' '.join(inputs.keys())

        for ecosystem, indicators in BUILD_INPUT_INDICATORS.items():
            for indicator in indicators:
                if indicator in input_names:
                    return ecosystem

    return None


def should_filter_cve(ecosystem: str, product: str, cve_vendor: str) -> bool:
    """
    Check if a CVE should be filtered out based on ecosystem mismatch.

    Args:
        ecosystem: Detected ecosystem (e.g., 'hackage')
        product: Product name (e.g., 'network')
        cve_vendor: Vendor from CVE CPE (e.g., 'fidelis')

    Returns:
        True if the CVE should be filtered (false positive)
    """
    key = (ecosystem, product.lower())
    if key in FALSE_POSITIVE_VENDORS:
        return cve_vendor.lower() in FALSE_POSITIVE_VENDORS[key]

    # Generic filter: ecosystem packages shouldn't match commercial vendors
    commercial_vendors = {
        'fidelis', 'hashicorp', 'cloudflare', 'f-secure', 'jenkins',
        'vmware', 'redhat', 'microsoft', 'oracle', 'cisco', 'sap',
        'adobe', 'apple', 'google', 'amazon', 'ibm', 'dell', 'hp',
    }

    if ecosystem and cve_vendor.lower() in commercial_vendors:
        return True

    return False


def extract_name_version(drv_path: str) -> tuple:
    """Extract package name and version from derivation path."""
    # Remove .drv extension and store path prefix
    name = Path(drv_path).stem
    if name.startswith('/nix/store/'):
        name = name.split('-', 1)[1] if '-' in name else name

    # Split name-version
    match = re.match(r'^(.+?)-(\d.*)$', name)
    if match:
        return match.group(1), match.group(2)
    return name, None


def analyze_derivation(drv_path: str) -> dict:
    """
    Analyze a derivation and return ecosystem information.

    Args:
        drv_path: Path to derivation

    Returns:
        Dict with analysis results
    """
    name, version = extract_name_version(drv_path)
    ecosystem = detect_ecosystem(drv_path)

    result = {
        'path': drv_path,
        'name': name,
        'version': version,
        'ecosystem': ecosystem,
        'vendor_hint': ecosystem,  # Can be used for CVE filtering
    }

    # Check for known false positive patterns
    if ecosystem:
        key = (ecosystem, name.lower())
        if key in FALSE_POSITIVE_VENDORS:
            result['known_fp_vendors'] = list(FALSE_POSITIVE_VENDORS[key])

    return result


def demo():
    """Demonstrate the ecosystem detection on sample paths."""
    test_paths = [
        '/nix/store/xxx-network-3.2.8.0.drv',
        '/nix/store/xxx-haskellPackages.vault-0.3.1.5.drv',
        '/nix/store/xxx-python311Packages.requests-2.28.0.drv',
        '/nix/store/xxx-nodePackages.async-2.2.5.drv',
        '/nix/store/xxx-warp-3.4.9.drv',  # Ambiguous without context
        '/nix/store/xxx-git-2.40.0.drv',  # System package
    ]

    print("Ecosystem Detection Demo")
    print("=" * 60)

    for path in test_paths:
        result = analyze_derivation(path)
        print(f"\nPath: {path}")
        print(f"  Name: {result['name']}")
        print(f"  Version: {result['version']}")
        print(f"  Ecosystem: {result['ecosystem'] or 'unknown'}")
        if result.get('known_fp_vendors'):
            print(f"  Known FP Vendors: {result['known_fp_vendors']}")


if __name__ == '__main__':
    if len(sys.argv) > 1:
        for path in sys.argv[1:]:
            result = analyze_derivation(path)
            print(json.dumps(result, indent=2))
    else:
        demo()

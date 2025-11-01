#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nodePackages.npm gnused jq

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "🔍 Checking for claude-code updates..."

# Get latest version from npm
latest_version=$(npm view @anthropic-ai/claude-code version)
echo "Latest version on npm: $latest_version"

# Get current version from flake.nix
current_version=$(grep -oP 'version = "\K[^"]+' flake.nix | head -1)
echo "Current version in flake: $current_version"

if [ "$latest_version" = "$current_version" ]; then
    echo "✅ Already at latest version!"
    exit 0
fi

echo "📦 Updating from $current_version to $latest_version..."

# Update version in flake.nix
sed -i "s/version = \"$current_version\"/version = \"$latest_version\"/" flake.nix
echo "✓ Updated version in flake.nix"

# Generate new package-lock.json
echo "📝 Generating package-lock.json..."
npm i --package-lock-only @anthropic-ai/claude-code@"$latest_version"
rm -f package.json
echo "✓ Generated package-lock.json"

# Build with placeholder to get source hash
echo "🔨 Building to get source hash..."
sed -i 's/hash = "sha256-[^"]*"/hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="/' flake.nix

build_output=$(nix build .#claude-code 2>&1 || true)
src_hash=$(echo "$build_output" | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' | head -1)

if [ -z "$src_hash" ]; then
    echo "❌ Failed to get source hash"
    exit 1
fi

echo "✓ Got source hash: $src_hash"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$src_hash\"|" flake.nix

# Build with placeholder to get npmDepsHash
echo "🔨 Building to get npmDepsHash..."
sed -i 's/npmDepsHash = "sha256-[^"]*"/npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="/' flake.nix

build_output=$(nix build .#claude-code 2>&1 || true)
npm_hash=$(echo "$build_output" | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' | tail -1)

if [ -z "$npm_hash" ]; then
    echo "❌ Failed to get npmDepsHash"
    exit 1
fi

echo "✓ Got npmDepsHash: $npm_hash"
sed -i "s|npmDepsHash = \"sha256-[^\"]*\"|npmDepsHash = \"$npm_hash\"|" flake.nix

# Final build to verify
echo "🔨 Final verification build..."
if nix build .#claude-code 2>&1; then
    echo "✅ Update complete!"
    echo ""
    echo "Summary:"
    echo "  Version: $current_version → $latest_version"
    echo "  Source hash: $src_hash"
    echo "  npmDepsHash: $npm_hash"
    echo ""
    echo "📋 Next steps:"
    echo "  1. Review the changes: git diff"
    echo "  2. Test the new version: nix run .#claude-code -- --version"
    echo "  3. Commit the changes if everything looks good"
else
    echo "❌ Final build failed. Please check the output above."
    exit 1
fi

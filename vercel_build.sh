#!/bin/bash
set -e

# Stay within Vercel container limits; dart2js inherits DART_VM_OPTIONS
export DART_VM_OPTIONS="--max-old-space-size=2048"
export NODE_OPTIONS="--max-old-space-size=2048"

# Force non-interactive so Flutter does not hang on analytics/permission around 25s
export GITHUB_ACTIONS=true
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true

# Nuclear clean: force full dependency graph rebuild in Linux (no stale/cross-platform artifacts)
rm -rf .dart_tool .packages pubspec.lock .flutter-plugins .flutter-plugins-dependencies

# Vercel uses Amazon Linux 2023 (dnf). Debian/Ubuntu use apt-get. Install deps for curl, git, tar, xz.
if command -v dnf &>/dev/null; then
  dnf install -y curl git xz tar zip
elif command -v apt-get &>/dev/null; then
  apt-get update && apt-get install -y curl git xz-utils zip libglu1-mesa
elif command -v yum &>/dev/null; then
  yum install -y curl git xz tar zip
fi

# Flutter 3.35.3 Linux (Vercel runs on Linux); matches pubspec.yaml sdk ">=3.6.0 <4.0.0"
FLUTTER_VERSION="3.35.3"
FLUTTER_TAR="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_TAR}"

echo "Downloading Flutter ${FLUTTER_VERSION}..."
curl -fL -o "$FLUTTER_TAR" "$FLUTTER_URL"

echo "Extracting Flutter..."
tar xf "$FLUTTER_TAR"
rm -f "$FLUTTER_TAR"

# Add flutter to PATH (tarball extracts to ./flutter)
export PATH="$PATH:$(pwd)/flutter/bin"

# Fix git ownership issue for flutter directory
git config --global --add safe.directory $(pwd)/flutter || true

flutter --version

# Use the exact 3.35.3 tarball (no upgrade) to avoid extra download/memory during setup
# Explicitly enable web so the build target is available
flutter config --enable-web

# Clean previous build artifacts
flutter clean

flutter pub get

# Build web with environment variables from Vercel
# Vercel environment variables are available as shell variables during build
# Check if variables are set (for debugging - won't fail if not set)
if [ -z "$SUPABASE_URL" ]; then
  echo "Warning: SUPABASE_URL environment variable is not set"
else
  echo "SUPABASE_URL is set (length: ${#SUPABASE_URL})"
fi
if [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "Warning: SUPABASE_ANON_KEY environment variable is not set"
else
  echo "SUPABASE_ANON_KEY is set (length: ${#SUPABASE_ANON_KEY})"
fi

# Clean compiler state: remove dart2js snapshot to avoid cfe-only / dart2js crashes
DART2JS_SNAPSHOT="$(pwd)/flutter/bin/cache/dart-sdk/bin/snapshots/dart2js.dart.snapshot"
if [ -f "$DART2JS_SNAPSHOT" ]; then
  echo "Removing dart2js snapshot for clean compiler state..."
  rm -f "$DART2JS_SNAPSHOT"
fi

# Align web toolchain (skip flutter doctor -v here to avoid extra processes before build)
./flutter/bin/flutter pub upgrade web

# Check lib size (if over 50MB, may contribute to OOM)
echo "=== lib/ size ==="
du -sh lib/ || true

# Show available RAM before build (kernel compile phase at ~25s is where OOM often hits)
echo "=== Memory before build (free -h) ==="
free -h || true

# Single-thread, low-memory build: --workers=1, --no-pub (we already ran pub get)
# Avoids spawning extra pub/dart processes during build that spike memory
# IMPORTANT: Do NOT use quotes around $VARIABLE - Flutter needs raw values
./flutter/bin/flutter build web --release --no-wasm --web-renderer html -O0 --no-source-maps --workers=1 --no-pub -v \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

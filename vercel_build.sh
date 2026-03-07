#!/bin/bash
set -e

# Stay within Vercel container limits; dart2js inherits DART_VM_OPTIONS
export DART_VM_OPTIONS="--max-old-space-size=2048"
export NODE_OPTIONS="--max-old-space-size=2048"

# Force non-interactive so Flutter does not hang on analytics/permission around 25s
export GITHUB_ACTIONS=true
export CI=true

# Nuclear clean: force full dependency graph rebuild in Linux (no stale/cross-platform artifacts)
rm -rf .dart_tool .packages pubspec.lock .flutter-plugins .flutter-plugins-dependencies

apt-get update
apt-get install -y curl git xz-utils zip libglu1-mesa

# Flutter 3.35.3 Linux (Vercel runs on Linux)
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

# Pin to stable and upgrade to latest patch (can fix minor bugs in 3.35.3)
./flutter/bin/flutter channel stable
./flutter/bin/flutter upgrade

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

# Show file structure before build (for debugging logs)
echo "=== Project file structure (ls -R) ==="
ls -R

# Clean compiler state: remove dart2js snapshot to avoid cfe-only / dart2js crashes
DART2JS_SNAPSHOT="$(pwd)/flutter/bin/cache/dart-sdk/bin/snapshots/dart2js.dart.snapshot"
if [ -f "$DART2JS_SNAPSHOT" ]; then
  echo "Removing dart2js snapshot for clean compiler state..."
  rm -f "$DART2JS_SNAPSHOT"
fi
flutter doctor -v

# Align web toolchain
./flutter/bin/flutter pub upgrade web

# Check lib size (if over 50MB, may contribute to OOM)
echo "=== lib/ size ==="
du -sh lib/ || true

# Build: -O0, --no-source-maps, --workers=1 (single worker to reduce peak memory)
# Project name in pubspec.yaml must be lowercase (pzed_homes)
# IMPORTANT: Do NOT use quotes around $VARIABLE - Flutter needs raw values
./flutter/bin/flutter build web --release --no-wasm --web-renderer html -O0 --no-source-maps --workers=1 -v \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

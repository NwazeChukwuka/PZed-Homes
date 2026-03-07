#!/bin/bash
set -e

apt-get update
apt-get install -y curl git xz-utils zip libglu1-mesa

# Flutter 3.33.0+ required for DropdownButtonFormField.initialValue and modern Dart
FLUTTER_VERSION="3.33.0"
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

# Clean previous build artifacts to avoid stale 3.27 (or older) files
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

# Build with dart-define flags (compatible with Flutter 3.33+)
# IMPORTANT: Do NOT use quotes around $VARIABLE - Flutter needs raw values
flutter build web --release --web-renderer html \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

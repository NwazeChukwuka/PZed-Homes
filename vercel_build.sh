#!/bin/bash

apt-get update

apt-get install -y curl git xz-utils zip libglu1-mesa

# Download newer Flutter version that includes Dart >= 3.9.2
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.27.0-stable.tar.xz

tar xf flutter_linux_3.27.0-stable.tar.xz

# Add flutter to PATH
export PATH="$PATH:$(pwd)/flutter/bin"

# Fix git ownership issue for flutter directory
git config --global --add safe.directory $(pwd)/flutter

flutter --version

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

# Build with dart-define flags
# IMPORTANT: Do NOT use quotes around $VARIABLE - Flutter needs raw values
flutter build web --release --web-renderer html \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

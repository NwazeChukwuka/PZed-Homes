#!/bin/bash
set -e  # Exit on error

echo "=== Installing system dependencies ==="
sudo apt-get update
sudo apt-get install -y curl git xz-utils zip libglu1-mesa

echo "=== Downloading Flutter ==="
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.3-stable.tar.xz

echo "=== Extracting Flutter ==="
tar xf flutter_linux_3.24.3-stable.tar.xz

echo "=== Setting up Flutter PATH ==="
export PATH="$PATH:$(pwd)/flutter/bin"

echo "=== Flutter version ==="
flutter --version

echo "=== Enabling web support ==="
flutter config --enable-web

echo "=== Getting dependencies ==="
flutter pub get

echo "=== Building web app ==="
flutter build web --release

echo "=== Build complete! Output in build/web ==="


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

flutter build web

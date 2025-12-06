#!/bin/bash

apt-get update

apt-get install -y curl git xz-utils zip libglu1-mesa

curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.3-stable.tar.xz

tar xf flutter_linux_3.24.3-stable.tar.xz

export PATH="$PATH:$(pwd)/flutter/bin"

flutter --version

flutter pub get

flutter build web

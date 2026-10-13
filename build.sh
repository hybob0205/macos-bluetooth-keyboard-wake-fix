#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="build/BluetoothKeyboardWakeFix.app"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/Info.plist"
MACOSX_DEPLOYMENT_TARGET=13.0 xcrun swiftc main.swift -framework AppKit -framework CoreBluetooth \
    -o "$app/Contents/MacOS/BluetoothKeyboardWakeFix"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
"$app/Contents/MacOS/BluetoothKeyboardWakeFix" --self-test
printf 'Built: %s/%s\n' "$PWD" "$app"

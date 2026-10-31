#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product TookMac
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/Took Mac.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/TookMac" "$app_dir/Contents/MacOS/TookMac"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ]; then
    swift Scripts/GenerateIcon.swift .build/AppIcon.iconset
    iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
ditto -c -k --keepParent "$app_dir" "$PWD/dist/Took-Mac.zip"
printf '앱 생성 완료: %s\n' "$app_dir"

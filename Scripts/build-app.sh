#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f Resources/AppIcon.icns ] || [ docs/assets/took-logo.png -nt Resources/AppIcon.icns ]; then
    swift Scripts/GenerateIcon.swift .build/AppIcon.iconset
    iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi
if command -v xcodegen >/dev/null 2>&1; then xcodegen generate; fi
build_args=(-project TookMac.xcodeproj -scheme TookMac -configuration Release -derivedDataPath .build/xcode)
if [ -n "${TOOK_DEVELOPMENT_TEAM:-}" ]; then
    xcodebuild "${build_args[@]}" "DEVELOPMENT_TEAM=$TOOK_DEVELOPMENT_TEAM" TOOK_STORAGE_MODE=group "TOOK_APP_GROUP=${TOOK_APP_GROUP:-group.local.tookmac.shared}" build
else
    xcodebuild "${build_args[@]}" CODE_SIGNING_ALLOWED=NO TOOK_STORAGE_MODE=local "TOOK_APP_GROUP=${TOOK_APP_GROUP:-group.local.tookmac.shared}" build
fi
mkdir -p dist
app_dir="$PWD/dist/Took Mac.app"
if [ -d "$app_dir" ]; then
    mv "$app_dir" "$PWD/.build/previous-package-$(date +%s).app"
fi
ditto '.build/xcode/Build/Products/Release/TookMac.app' "$app_dir"
if [ -z "${TOOK_DEVELOPMENT_TEAM:-}" ]; then
    cp Configuration/local.entitlements .build/local.entitlements
    codesign --force --sign - --entitlements .build/local.entitlements "$app_dir/Contents/PlugIns/TookWidgets.appex"
    codesign --force --sign - --entitlements Configuration/local-app.entitlements "$app_dir"
fi
for version_key in CFBundleVersion CFBundleShortVersionString; do
    app_version="$(plutil -extract "$version_key" raw -o - "$app_dir/Contents/Info.plist")"
    widget_version="$(plutil -extract "$version_key" raw -o - "$app_dir/Contents/PlugIns/TookWidgets.appex/Contents/Info.plist")"
    if [ "$app_version" != "$widget_version" ]; then
        printf '앱과 위젯 버전이 다릅니다: %s / %s\n' "$app_version" "$widget_version" >&2
        exit 1
    fi
done
codesign --verify --deep --strict "$app_dir"
ditto -c -k --keepParent "$app_dir" "$PWD/dist/Took-Mac.zip"
printf '앱과 정식 위젯 생성 완료: %s\n' "$app_dir"

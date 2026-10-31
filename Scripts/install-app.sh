#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/build-app.sh

install_dir="$HOME/Applications/Took Mac.app"
register_tool=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
swift -e 'import AppKit; for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.tookmac.desktop") { app.terminate() }'
for attempt in 1 2 3 4 5; do
    if ! pgrep -x TookMac >/dev/null; then break; fi
    sleep 1
done
if pgrep -x TookMac >/dev/null; then
    printf 'Took Mac을 종료한 다음 다시 설치해 주세요.\n' >&2
    exit 1
fi
# 개발본을 함께 등록하면 WidgetKit이 서로 다른 번들 버전을 혼합할 수 있다.
/usr/bin/pluginkit -r "$PWD/dist/Took Mac.app/Contents/PlugIns/TookWidgets.appex" 2>/dev/null || true
"$register_tool" -u "$PWD/dist/Took Mac.app" 2>/dev/null || true
if [ -d "$install_dir" ]; then
    "$register_tool" -u "$install_dir" 2>/dev/null || true
fi
mkdir -p "$HOME/Applications"
ditto 'dist/Took Mac.app' "$install_dir"
"$register_tool" -f "$install_dir"
/usr/bin/pluginkit -a "$install_dir/Contents/PlugIns/TookWidgets.appex"
open "$install_dir"
"$install_dir/Contents/MacOS/TookMac" --widget-check
printf '설치와 위젯 등록 완료: %s\n' "$install_dir"

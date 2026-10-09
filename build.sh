#!/bin/zsh
# Builds "Local Git List.app" into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "${0:A:h}"

swift build -c release --arch arm64 --arch x86_64
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

app="build/Local Git List.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/LocalGitList" "$app/Contents/MacOS/LocalGitList"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x LocalGitList || true
  rm -rf "/Applications/Local Git List.app"
  cp -R "$app" /Applications/
  open "/Applications/Local Git List.app"
  echo "Installed /Applications/Local Git List.app"
fi

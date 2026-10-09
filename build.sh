#!/bin/zsh
# Builds "Local Git List.app" into ./build.
#   ./build.sh            build the app (ad-hoc signed unless SIGN_IDENTITY is set)
#   ./build.sh --install  also copy it to /Applications and launch it
#   ./build.sh --dmg      also build build/LocalGitList.dmg; with SIGN_IDENTITY and NOTARY_PROFILE
#                         set, the app and dmg are Developer ID signed, notarized and stapled
#
# SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
# NOTARY_PROFILE  keychain profile from `xcrun notarytool store-credentials`
set -euo pipefail
cd "${0:A:h}"

swift build -c release --arch arm64 --arch x86_64
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

app="build/Local Git List.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/LocalGitList" "$app/Contents/MacOS/LocalGitList"
cp Resources/Info.plist "$app/Contents/Info.plist"

identity="${SIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$app"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
  codesign --verify --strict --verbose=2 "$app"
fi
echo "Built $app (signed as: ${identity/#-/ad-hoc})"

if [[ "${1:-}" == "--dmg" ]]; then
  dmg="build/LocalGitList.dmg"
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  cp -R "$app" "$stage/"
  ln -s /Applications "$stage/Applications"
  rm -f "$dmg"
  hdiutil create -volname "Local Git List" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null

  if [[ "$identity" != "-" ]]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
      xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
      xcrun stapler staple "$dmg"
      spctl --assess --type open --context context:primary-signature --verbose "$dmg"
    else
      echo "NOTARY_PROFILE not set: dmg is signed but not notarized"
    fi
  else
    echo "Ad-hoc signed dmg: users must approve it in System Settings > Privacy & Security"
  fi
  echo "Built $dmg"
fi

if [[ "${1:-}" == "--install" ]]; then
  pkill -x LocalGitList || true
  rm -rf "/Applications/Local Git List.app"
  cp -R "$app" /Applications/
  open "/Applications/Local Git List.app"
  echo "Installed /Applications/Local Git List.app"
fi

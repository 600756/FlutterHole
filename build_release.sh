#!/usr/bin/env bash
set -euo pipefail

release_dir="release"
mkdir -p "$release_dir"

flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "$release_dir/FlutterHole.apk"

flutter build macos --release
macos_app_path="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$macos_app_path" ]]; then
  echo "MacOS app not found in build/macos/Build/Products/Release" >&2
  exit 1
fi
tmp_dmg_dir="$(mktemp -d)"
cp -R "$macos_app_path" "$tmp_dmg_dir/"
hdiutil create -volname "FlutterHole" -srcfolder "$tmp_dmg_dir/" -ov -format UDZO "$release_dir/FlutterHole.dmg"
rm -rf "$tmp_dmg_dir"

flutter build ios --release --no-codesign
tmp_payload_dir="$(mktemp -d)"
mkdir -p "$tmp_payload_dir/Payload"
cp -R build/ios/iphoneos/Runner.app "$tmp_payload_dir/Payload/"
(cd "$tmp_payload_dir" && zip -qr "$OLDPWD/$release_dir/FlutterHole.ipa" Payload)
rm -rf "$tmp_payload_dir"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/fetch-tracker.py
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/Tony Stark.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks" "$app_dir/Contents/Resources/MediaPipe"
cp "$bin_dir/TonyStark" "$app_dir/Contents/MacOS/TonyStark"
cp vendor/mediapipe/libmediapipe.dylib "$app_dir/Contents/Frameworks/libmediapipe.dylib"
cp vendor/mediapipe/hand_landmarker.task "$app_dir/Contents/Resources/hand_landmarker.task"
cp vendor/mediapipe/LICENSE vendor/mediapipe/NOTICE "$app_dir/Contents/Resources/MediaPipe/"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>TonyStark</string>
  <key>CFBundleIdentifier</key><string>tech.studyd.tonystark.gestures</string>
  <key>CFBundleName</key><string>Tony Stark</string>
  <key>CFBundleDisplayName</key><string>Tony Stark</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>Track your hand locally to preview gestures and control Mac windows. Camera frames are not recorded or uploaded.</string>
</dict></plist>
PLIST
# A stable local identity is available through SIGN_IDENTITY. Ad-hoc signing
# works for development, but macOS may ask for Accessibility again after rebuilds.
codesign --force --sign "${SIGN_IDENTITY:--}" "$app_dir/Contents/Frameworks/libmediapipe.dylib"
codesign --force --sign "${SIGN_IDENTITY:--}" "$app_dir"
printf 'Built: %s\n' "$app_dir"

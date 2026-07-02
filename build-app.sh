#!/usr/bin/env bash
# Build the Flutter app artifacts and place them where the PHP server
# expects them:
#   - Android APK  → public/download/gullify.apk (served at /download/)
# Requires the Flutter SDK on PATH.
set -euo pipefail
cd "$(dirname "$0")/app"

flutter pub get
flutter build apk --release

cp build/app/outputs/flutter-apk/app-release.apk ../public/download/gullify.apk
echo "APK publié: public/download/gullify.apk"

#!/usr/bin/env bash
# Build the Flutter app artifacts and place them where the PHP server
# expects them:
#   - Android APK  → public/download/gullify.apk (served at /download/)
#   - version.json → public/download/version.json (auto-update manifest)
# If the static download dir exists (download.gullify.app), publish there
# too: versioned APK, gullify-latest.apk symlink and version.json.
#
# Usage: ./build-app.sh ["changelog de la version"]
# Requires the Flutter SDK on PATH.
set -euo pipefail
cd "$(dirname "$0")/app"

CHANGELOG="${1:-}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/home/maxime/gullify-server/downloads}"

# Version depuis pubspec.yaml (ex. "2.1.0+28" → name=2.1.0, code=28)
VERSION_FULL=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
VERSION_NAME="${VERSION_FULL%+*}"
VERSION_CODE="${VERSION_FULL#*+}"

flutter pub get
flutter build apk --release

cp build/app/outputs/flutter-apk/app-release.apk ../public/download/gullify.apk

cat > ../public/download/version.json <<EOF
{
  "versionCode": $VERSION_CODE,
  "versionName": "$VERSION_NAME",
  "downloadUrl": "https://download.gullify.app/gullify-$VERSION_NAME.apk",
  "latestUrl": "https://download.gullify.app/gullify-latest.apk",
  "changelog": $(printf '%s' "$CHANGELOG" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "releasedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "APK publié: public/download/gullify.apk (v$VERSION_NAME, code $VERSION_CODE)"

if [ -d "$DOWNLOAD_DIR" ]; then
  cp ../public/download/gullify.apk "$DOWNLOAD_DIR/gullify-$VERSION_NAME.apk"
  cp ../public/download/gullify.apk "$DOWNLOAD_DIR/gullify.apk"
  ln -sfn "gullify-$VERSION_NAME.apk" "$DOWNLOAD_DIR/gullify-latest.apk"
  cp ../public/download/version.json "$DOWNLOAD_DIR/version.json"
  echo "Publié sur download.gullify.app: gullify-$VERSION_NAME.apk (+ latest, version.json)"
fi

#!/usr/bin/env bash
# Build the Flutter app artifacts and place them where the PHP server
# expects them:
#   - Android APK  → public/download/gullify.apk (served at /download/)
#   - version.json → public/download/version.json (auto-update manifest)
# If the static download dir exists (download.gullify.app), publish there
# too: versioned APK, gullify-latest.apk symlink and version.json.
# Puis la version web (/app/), construite du même code : une version de l'app
# sort sur les deux à la fois, jamais l'APK seul (idée #121).
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

# L'historique des versions doit parler de celle qu'on livre.
#
# Il est tenu à la main, et il avait pris trois versions de retard sans que
# rien ne le dise — comme le numéro de version affiché dans Paramètres, écrit
# en dur, resté à 3.71.0 pendant que l'app partait en 3.73. Celui-là est
# maintenant demandé au système ; celui-ci se vérifie ici, pendant qu'il est
# encore temps d'écrire la note.
TETE_CHANGELOG=$(grep -m1 -oP "ReleaseNote\('\K[^']+" lib/changelog.dart || true)
if [ "$TETE_CHANGELOG" != "$VERSION_NAME" ]; then
  echo "lib/changelog.dart commence par « $TETE_CHANGELOG », or on livre la $VERSION_NAME." >&2
  echo "Ajoute l'entrée de la $VERSION_NAME en tête, puis relance." >&2
  exit 1
fi

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

# ── La même version pour le web (idée #121) ─────────────────────────────────
# Le web est servi depuis public/app/. Si le conteneur monte ce dossier, la
# copie de build-web.sh suffit ; sinon l'image doit être reconstruite.
cd ..
./build-web.sh
if docker inspect gullify --format '{{range .Mounts}}{{println .Destination}}{{end}}' 2>/dev/null \
     | grep -qx '/app/public/app'; then
  echo "Web en ligne : gullify.app/app/ sert la v$VERSION_NAME."
else
  echo "⚠️  public/app/ n'est pas monté dans le conteneur : lancer" \
       "./build-web.sh --deploy pour mettre le web en ligne." >&2
fi

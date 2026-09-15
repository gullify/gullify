#!/usr/bin/env bash
# Construit la version web de l'app Flutter — la MÊME que l'APK, même code,
# même interface — et la place là où le serveur PHP la sert :
#   public/app/  →  https://gullify.app/app/
#
# Le conteneur embarque une copie du dépôt (COPY . /app/ dans le Dockerfile) :
# il faut donc reconstruire l'image pour que le serveur voie la nouvelle
# version. `--deploy` s'en charge.
#
# Usage: ./build-web.sh [--deploy]
# Requiert le SDK Flutter sur le PATH.
set -euo pipefail
cd "$(dirname "$0")"

BASE_HREF="${BASE_HREF:-/app/}"
DEST="public${BASE_HREF%/}"

cd app
flutter pub get
flutter build web --release --base-href "$BASE_HREF"

# Le service worker de Flutter se DÉSINSCRIT de lui-même (Flutter ne met plus
# rien en cache par défaut) : l'app se retrouve sans service worker actif, et
# un navigateur n'y voit alors plus une application installable — seulement
# une page à raccourcir. On lui substitue le nôtre, qui ne met rien en cache
# non plus mais expose le gestionnaire `fetch` exigé. Voir tool/service_worker.js.
cp tool/service_worker.js build/web/flutter_service_worker.js

# La version du code DANS l'adresse de main.dart.js. Flutter garde le même nom
# de fichier d'une version à l'autre, et un navigateur qui en a une copie peut
# la resservir sans jamais redemander au serveur, quelles que soient les
# consignes de cache — c'est ce qu'a fait une app installée sur Windows. Une
# adresse qu'il n'a jamais vue, il est bien obligé d'aller la chercher.
# L'empreinte ne change qu'avec le contenu : le cache sert toujours entre deux
# constructions identiques. flutter_bootstrap.js, qui porte l'adresse, est lui
# revalidé à chaque ouverture (voir public/.htaccess).
MAIN_HASH=$(md5sum build/web/main.dart.js | cut -c1-12)
if ! grep -q '"mainJsPath":"main.dart.js"' build/web/flutter_bootstrap.js; then
  echo "build-web.sh : mainJsPath introuvable dans flutter_bootstrap.js —" \
       "le format de Flutter a changé, main.dart.js ne serait pas versionné." >&2
  exit 1
fi
sed -i "s#\"mainJsPath\":\"main.dart.js\"#\"mainJsPath\":\"main.dart.js?v=$MAIN_HASH\"#" \
  build/web/flutter_bootstrap.js
cd ..

rm -rf "$DEST"
cp -r app/build/web "$DEST"
echo "Web publié: $DEST (base href $BASE_HREF, $(du -sh "$DEST" | cut -f1))"

if [ "${1:-}" = "--deploy" ]; then
  docker compose build --build-arg CACHEBUST="$(date +%s)" app
  docker compose up -d app
  echo "Conteneur redéployé."
fi

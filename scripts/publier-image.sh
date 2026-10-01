#!/usr/bin/env bash
# Publie l'image du serveur dans le dépôt d'où les gens l'installent.
#
# À passer à chaque version : sans cela, les nouvelles installations posent
# l'ancienne. Le mot de passe d'écriture vit dans
# /home/maxime/gullify-registre/motdepasse-pousse.txt, et nulle part ailleurs.
set -euo pipefail
cd "$(dirname "$0")/.."

DEPOT="${DEPOT:-registry.gullify.app/gullify}"
MDP_FICHIER="${MDP_FICHIER:-/home/maxime/gullify-registre/motdepasse-pousse.txt}"
VERSION="$(grep '^version:' app/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"

echo "Construction de l'image…"
docker compose build --build-arg CACHEBUST="$(date +%s)" app

echo "Publication de $DEPOT:$VERSION"
docker login "${DEPOT%%/*}" -u gullify --password-stdin < "$MDP_FICHIER"
docker tag gullify-app "$DEPOT:$VERSION"
docker tag gullify-app "$DEPOT:latest"
docker push "$DEPOT:$VERSION"
docker push "$DEPOT:latest"
docker logout "${DEPOT%%/*}"

echo
echo "Publié. Les versions disponibles :"
curl -s "https://${DEPOT%%/*}/v2/${DEPOT#*/}/tags/list"
echo

#!/usr/bin/env bash
# Publie l'image du serveur dans le dépôt d'où les gens l'installent.
#
# À passer à chaque version : sans cela, les nouvelles installations posent
# l'ancienne. Le mot de passe d'écriture vit dans
# /home/maxime/gullify-registre/motdepasse-pousse.txt, et nulle part ailleurs.
#
# Le numéro vient du fichier VERSION, à la racine. Le SERVEUR a sa propre
# numérotation, par date — AAAA.MM.N, N étant la énième sortie du mois — et
# non celle de l'app : ils ne sortent pas ensemble, leurs utilisateurs ne les
# mettent pas à jour en même temps, et deux choses différentes qui portent le
# même numéro finissent toujours par être confondues. Le même fichier est
# copié dans l'image (voir Dockerfile), si bien qu'un serveur dit toujours
# exactement l'étiquette sous laquelle il a été publié.
set -euo pipefail
cd "$(dirname "$0")/.."

DEPOT="${DEPOT:-registry.gullify.app/gullify}"
MDP_FICHIER="${MDP_FICHIER:-/home/maxime/gullify-registre/motdepasse-pousse.txt}"
VERSION="$(tr -d '[:space:]' < VERSION)"

if [ -z "$VERSION" ]; then
  echo "Le fichier VERSION est vide." >&2
  exit 1
fi

# Republier sous un numéro déjà pris remplacerait l'image de ce numéro sans
# rien dire : les serveurs qui s'y croient à jour le resteraient, avec autre
# chose dans le ventre.
if curl -sf "https://${DEPOT%%/*}/v2/${DEPOT#*/}/tags/list" |
   grep -q "\"$VERSION\""; then
  if [ "${1:-}" != "--republier" ]; then
    echo "La version $VERSION est déjà publiée." >&2
    echo "Change le fichier VERSION, ou passe --republier pour l'écraser." >&2
    exit 1
  fi
  echo "⚠ $VERSION est déjà publiée : elle va être remplacée."
fi

echo "Construction de l'image du serveur $VERSION…"
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

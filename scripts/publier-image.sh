#!/usr/bin/env bash
# Publie l'image du serveur dans le dépôt d'où les gens l'installent.
#
# À passer à chaque version : sans cela, les nouvelles installations posent
# l'ancienne. Le mot de passe d'écriture vit dans
# /home/maxime/gullify-registre/motdepasse-pousse.txt, et nulle part ailleurs.
#
# Le numéro vient du fichier VERSION, à la racine. Le SERVEUR a sa propre
# numérotation — majeur.mineur.correctif — et non celle de l'app : ils ne
# sortent pas ensemble, leurs utilisateurs ne les mettent pas à jour en même
# temps, et deux choses différentes qui portent le même numéro finissent
# toujours par être confondues. Le même fichier est copié dans l'image (voir
# Dockerfile), si bien qu'un serveur dit toujours exactement l'étiquette sous
# laquelle il a été publié.
#
#   correctif : une réparation, rien à faire de particulier ;
#   mineur    : du nouveau, qui n'exige rien de l'installation existante ;
#   majeur    : une mise à jour qui demande une intervention (réglages,
#               base de données, installateur à relancer).
#
# Usage : ./scripts/publier-image.sh ["ce qui change, en une phrase"]
set -euo pipefail
cd "$(dirname "$0")/.."

DEPOT="${DEPOT:-registry.gullify.app/gullify}"
MDP_FICHIER="${MDP_FICHIER:-/home/maxime/gullify-registre/motdepasse-pousse.txt}"
MANIFESTE_DIR="${MANIFESTE_DIR:-/home/maxime/gullify-server/downloads}"
VERSION="$(tr -d '[:space:]' < VERSION)"
NOTE="${1:-}"
[ "$NOTE" = "--republier" ] && NOTE=""

if [ -z "$VERSION" ]; then
  echo "Le fichier VERSION est vide." >&2
  exit 1
fi

# Republier sous un numéro déjà pris remplacerait l'image de ce numéro sans
# rien dire : les serveurs qui s'y croient à jour le resteraient, avec autre
# chose dans le ventre.
if curl -sf "https://${DEPOT%%/*}/v2/${DEPOT#*/}/tags/list" |
   grep -q "\"$VERSION\""; then
  if [ "${1:-}" != "--republier" ] && [ "${2:-}" != "--republier" ]; then
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

# Le manifeste : c'est LUI que les serveurs interrogent pour savoir s'ils sont
# en retard, et non la liste des étiquettes du dépôt — celle-ci garde pour
# toujours les numéros d'avant, quand le serveur portait ceux de l'app, et un
# serveur en 1.x s'y croirait en retard de 3.73 à jamais.
if [ -d "$MANIFESTE_DIR" ]; then
  cat > "$MANIFESTE_DIR/serveur.json" <<JSON
{
  "version": "$VERSION",
  "image": "$DEPOT:$VERSION",
  "publiee": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "notes": $(printf '%s' "$NOTE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
}
JSON
  echo "Manifeste écrit : $MANIFESTE_DIR/serveur.json"
else
  echo "⚠ $MANIFESTE_DIR est introuvable : le manifeste n'a PAS été écrit," >&2
  echo "  donc aucun serveur ne saura que $VERSION existe." >&2
fi

echo
echo "Publié. Les versions disponibles :"
curl -s "https://${DEPOT%%/*}/v2/${DEPOT#*/}/tags/list"
echo

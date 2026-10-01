#!/usr/bin/env bash
# Fabrique l'installateur pour les trois systèmes, depuis n'importe lequel.
#
# C'est tout l'intérêt d'avoir choisi Go : pas besoin d'un Mac pour fabriquer la
# version Mac, ni d'une machine Windows pour la version Windows. Le résultat
# tient dans un fichier par système, sans rien à installer autour.
#
# Usage : ./construire.sh [dossier-de-sortie]
set -euo pipefail
cd "$(dirname "$0")"

SORTIE="${1:-../public/download/installateur}"
mkdir -p "$SORTIE"

GO="${GO:-/usr/local/go/bin/go}"
VERSION="$(git describe --tags --always 2>/dev/null || echo inconnue)"

# -s -w retire les tables de symboles : le fichier descend d'un bon quart, et
# personne n'a besoin d'y déboguer.
DRAPEAUX="-s -w -X main.version=$VERSION"

fabrique() { # $1=système $2=architecture $3=suffixe
  local nom="gullify-installateur-$1-$2$3"
  echo "  $nom"
  GOOS="$1" GOARCH="$2" CGO_ENABLED=0 "$GO" build -trimpath -ldflags "$DRAPEAUX" -o "$SORTIE/$nom" .
}

echo "Fabrication ($VERSION) :"
fabrique linux   amd64 ""
fabrique linux   arm64 ""
fabrique windows amd64 ".exe"
fabrique darwin  amd64 ""
fabrique darwin  arm64 ""

echo
ls -lh "$SORTIE" | awk 'NR>1 {print "  "$9"  "$5}'
echo
echo "Rappel : ces fichiers ne sont pas signés. Windows affichera « Éditeur"
echo "inconnu » et macOS refusera le premier lancement — la page d'aide doit"
echo "accompagner le téléchargement."

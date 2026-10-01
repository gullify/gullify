#!/usr/bin/env bash
# Le compagnon GulliFY : le bras du serveur, hors de son conteneur.
#
# Un conteneur ne peut ni se redémarrer ni se remplacer lui-même — il faut
# quelqu'un dehors. Ce quelqu'un tourne donc sur la machine, en tant que la
# personne qui a installé le serveur, et n'écoute AUCUN port : il regarde
# simplement, toutes les dix secondes, si le serveur a déposé une demande
# dans son dossier de données. Seul un administrateur connecté peut l'y
# faire déposer (voir public/api/v2/update.php).
#
# C'est volontairement le chemin le plus bête : rien à ouvrir, rien à
# authentifier, et aucun conteneur ne tient le socket Docker.
#
# Usage :
#   gullify-compagnon.sh <projet-compose> <dossier-de-la-pile> [dossier-du-code]
#
#   Avec un dossier de code (serveur installé depuis le dépôt), mettre à jour
#   = `git pull` puis reconstruire l'image. Sans lui (serveur posé par
#   l'installateur), = tirer l'image déjà construite.
set -uo pipefail

PROJET="${1:?il faut le nom du projet compose}"
PILE="${2:?il faut le dossier de la pile}"
SOURCE="${3:-}"

INTERVALLE="${GULLIFY_COMPAGNON_INTERVALLE:-10}"
TAMPON="$(mktemp -t gullify-compagnon-XXXXXX)"
trap 'rm -f "$TAMPON"' EXIT

# ── Parler au serveur ────────────────────────────────────────────────────────

# Le conteneur change de nom à chaque recréation : on le redemande à chaque
# fois plutôt que de garder une référence qui périme au pire moment.
conteneur() { docker compose -p "$PROJET" ps -q app 2>/dev/null | head -1; }

# -u 1000 : dans le conteneur, PUID remappe www-data sur l'uid 1000. Les
# fichiers qu'on dépose doivent lui appartenir, sinon PHP ne peut plus les
# réécrire — et la demande suivante resterait sans réponse.
dans_le_serveur() {
  local c; c="$(conteneur)" || return 1
  [ -n "$c" ] || return 1
  docker exec -u 1000:1000 -i "$c" "$@" 2>/dev/null
}

dit() {
  printf '%s\n' "$*" | tee -a "$TAMPON"
  pousse_journal
}

# Le journal vit dans le volume de données, là où le serveur le lit. Pendant
# qu'il redémarre, il n'y a personne pour l'écrire : on le garde sous le coude
# et on le pousse dès que quelqu'un répond.
pousse_journal() {
  dans_le_serveur sh -c 'cat > /app/data/maj/journal' < "$TAMPON" || true
}

# ── Les deux gestes ──────────────────────────────────────────────────────────

redemarrer() {
  : > "$TAMPON"
  dit "Redémarrage du serveur..."
  if (cd "$PILE" && docker compose -p "$PROJET" restart app >/dev/null 2>&1); then
    attendre_le_retour
    dit "fini"
  else
    dit "Le redémarrage a échoué."
    dit "fini"
  fi
}

mettre_a_jour() {
  : > "$TAMPON"

  if [ -n "$SOURCE" ]; then
    dit "Récupération du code..."
    if ! git -C "$SOURCE" pull --ff-only >/dev/null 2>&1; then
      dit "Le code n'a pas pu être récupéré (dépôt modifié sur place ?)."
      dit "fini"
      return
    fi
    dit "Construction de la nouvelle version... (quelques minutes)"
    if ! (cd "$SOURCE" && docker compose build app >/dev/null 2>&1); then
      dit "La construction a échoué."
      dit "fini"
      return
    fi
  else
    dit "Téléchargement de la nouvelle version..."
    if ! (cd "$PILE" && docker compose -p "$PROJET" pull app >/dev/null 2>&1); then
      dit "Le téléchargement a échoué."
      dit "fini"
      return
    fi
  fi

  dit "Mise en place..."
  if (cd "$PILE" && docker compose -p "$PROJET" up -d --force-recreate app >/dev/null 2>&1); then
    attendre_le_retour
    dit "fini"
  else
    dit "La mise en place a échoué — l'ancienne version tourne toujours."
    dit "fini"
  fi
}

# Le serveur met un moment à répondre après une recréation (yt-dlp se met à
# jour avant Apache). « Le conteneur tourne » ne suffit donc pas : on attend
# qu'il RÉPONDE, sans quoi « fini » s'écrirait sur un serveur encore muet.
attendre_le_retour() {
  for _ in $(seq 1 60); do
    if dans_le_serveur curl -sf -o /dev/null http://localhost/ >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

# ── La boucle ────────────────────────────────────────────────────────────────

echo "Compagnon GulliFY : projet $PROJET, pile $PILE${SOURCE:+, code $SOURCE}"

while true; do
  if [ -n "$(conteneur)" ]; then
    # Le signe de vie : c'est lui qui fait apparaître les boutons dans l'app.
    # 0777 sur le dossier, parce que les deux côtés y écrivent.
    dans_le_serveur sh -c \
      '[ -d /app/data/maj ] || { mkdir -p /app/data/maj; chmod 0777 /app/data/maj; }
       touch /app/data/maj/present' || true

    demande="$(dans_le_serveur sh -c \
      'if [ -f /app/data/maj/demande ]; then cat /app/data/maj/demande; rm -f /app/data/maj/demande; fi')"

    case "$demande" in
      redemarrer) redemarrer ;;
      maj)        mettre_a_jour ;;
    esac
  fi
  sleep "$INTERVALLE"
done

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
# Quatre demandes : « redemarrer », « maj », « lister <chemin> » (les dossiers
# de la machine, que le conteneur ne voit pas — il ne connaît que ce qui lui
# est monté) et « racine <chemin> » (changer le dossier de musique, ce qui
# veut dire réécrire MUSIC_HOST_PATH et remonter la pile).
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
EVEIL=0        # tant que l'horloge n'a pas dépassé ça, on sonde chaque seconde
MAX_SONDE=40       # au-delà, on ne regarde plus dossier par dossier s'il y a de la musique
MAX_DOSSIERS=300   # au-delà, la liste est écourtée : aucun écran ne déroule mille entrées
vus=""         # les dossiers déjà proposés au départ
TAMPON="$(mktemp -t gullify-compagnon-XXXXXX)"   # le journal en attente
SORTIE="$(mktemp -t gullify-sortie-XXXXXX)"      # ce qu'a dit la dernière commande
trap 'rm -f "$TAMPON" "$SORTIE"' EXIT

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
    if ! essaie git -C "$SOURCE" pull --ff-only; then
      dit "Le code n'a pas pu être récupéré (dépôt modifié sur place ?)."
      raconte_l_echec
      return
    fi
    dit "Construction de la nouvelle version... (quelques minutes)"
    # Rien à passer : le numéro du serveur vit dans le fichier VERSION du
    # dépôt, que la construction copie dans l'image. Tant qu'il arrivait par
    # une option, une construction qui l'oubliait donnait un serveur sans âge.
    if ! (cd "$SOURCE" && essaie docker compose build app); then
      dit "La construction a échoué."
      raconte_l_echec
      return
    fi
  else
    dit "Téléchargement de la nouvelle version..."
    if ! (cd "$PILE" && essaie docker compose -p "$PROJET" pull app); then
      dit "Le téléchargement a échoué."
      raconte_l_echec
      return
    fi
  fi

  dit "Mise en place..."
  if (cd "$PILE" && essaie docker compose -p "$PROJET" up -d --force-recreate app); then
    attendre_le_retour
    dit "fini"
  else
    dit "La mise en place a échoué — l'ancienne version tourne toujours."
    raconte_l_echec
  fi
}

# ── Voir la machine à la place du conteneur ──────────────────────────────────
#
# Le conteneur ne voit que ce qu'on lui a monté : demander « où est ma
# musique ? » depuis l'app, c'est demander à quelqu'un qui n'a pas d'yeux. Le
# compagnon, lui, est sur la machine — il regarde pour lui.

# Une chaîne JSON : seuls le guillemet et la barre obliquée inverse comptent
# pour un nom de dossier.
json_chaine() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# Les dossiers d'un chemin, en JSON, avec de quoi décider sans ouvrir : le
# nombre de sous-dossiers, et si on y trouve de la musique en surface.
lister() {
  local chemin="$1"
  : > "$TAMPON"

  # Sans chemin, on propose les endroits où la musique se trouve d'habitude :
  # les disques montés (clés USB comprises), le dossier personnel, et la
  # racine actuelle. Personne ne devrait avoir à taper « /media/maxime ».
  if [ -z "$chemin" ] || [ "$chemin" = "depart" ]; then
    repond_depart
    return
  fi

  if [ ! -d "$chemin" ]; then
    repond_erreur "$chemin" "Ce dossier n'existe pas (ou n'est pas lisible d'ici)."
    return
  fi

  local sortie="{\"chemin\":$(json_chaine "$chemin")"
  local parent="${chemin%/*}"; [ -z "$parent" ] && parent="/"
  [ "$parent" != "$chemin" ] && sortie="$sortie,\"parent\":$(json_chaine "$parent")"
  sortie="$sortie,\"musique\":$(compte_musique "$chemin")"

  # Un dossier d'artistes en compte des centaines, et sonder chacun d'eux
  # coûtait sept secondes à l'ouverture. Au-delà d'une poignée, on se contente
  # donc de les nommer : l'indice « il y a de la musique là-dedans » sert en
  # haut de l'arbre, là où l'on hésite entre deux disques — pas au milieu
  # d'une discographie, où la question ne se pose plus.
  local total; total="$(find "$chemin" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
  local sonde=1
  [ "$total" -gt "$MAX_SONDE" ] && sonde=0
  [ "$total" -gt "$MAX_DOSSIERS" ] && sortie="$sortie,\"tronque\":true"
  sortie="$sortie,\"dossiers\":["

  local premier=1 entree nom rendus=0
  while IFS= read -r entree; do
    nom="${entree##*/}"
    case "$nom" in .*) continue ;; esac
    [ $premier -eq 1 ] || sortie="$sortie,"
    premier=0
    sortie="$sortie{\"nom\":$(json_chaine "$nom")"
    sortie="$sortie,\"chemin\":$(json_chaine "$entree")"
    # -1 : « je n'ai pas regardé », qui ne se dit pas comme « il n'y a rien ».
    if [ $sonde -eq 1 ]; then
      sortie="$sortie,\"musique\":$(compte_musique "$entree")}"
    else
      sortie="$sortie,\"musique\":-1}"
    fi
    rendus=$((rendus + 1))
    [ "$rendus" -ge "$MAX_DOSSIERS" ] && break
  done < <(find "$chemin" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

  repond "$sortie]}"
}

# Combien de fichiers audio près de la surface — trois niveaux, de quoi
# traverser artiste/album/titre, et pas un de plus : on ne cherche ici qu'un
# indice (ce dossier-ci est-il la bibliothèque ?), pas un inventaire. La
# recherche s'arrête d'elle-même aux cinquante premiers.
compte_musique() {
  find "$1" -maxdepth 3 -type f \
    \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' -o -iname '*.ogg' \
       -o -iname '*.opus' -o -iname '*.wav' -o -iname '*.aac' \) \
    2>/dev/null | head -50 | wc -l
}

# Les points de départ : ce qui est monté (/media, /mnt), le dossier
# personnel, et là où le serveur lit en ce moment.
repond_depart() {
  local sortie="{\"chemin\":\"\",\"depart\":true,\"dossiers\":["
  local premier=1 c nom
  # Remis à zéro à CHAQUE fois : gardée d'un appel sur l'autre, cette liste
  # faisait un deuxième écran de départ entièrement vide — tout y était déjà
  # « déjà proposé ».
  vus=""
  for c in /media/* /media/*/* /mnt/* "$HOME" "$HOME/Musique" "$HOME/Music" \
           "$(racine_actuelle)"; do
    [ -d "$c" ] || continue
    # Un même dossier proposé deux fois (la racine est souvent sous /media)
    # ferait douter de ce qu'on voit.
    case ",$vus," in *",$c,"*) continue ;; esac
    vus="$vus,$c"
    nom="${c##*/}"
    [ $premier -eq 1 ] || sortie="$sortie,"
    premier=0
    sortie="$sortie{\"nom\":$(json_chaine "$nom"),\"chemin\":$(json_chaine "$c")"
    sortie="$sortie,\"musique\":$(compte_musique "$c")}"
  done
  repond "$sortie]}"
}

# La racine que la pile lit en ce moment, telle qu'écrite dans son .env.
racine_actuelle() {
  [ -f "$PILE/.env" ] || return 0
  sed -n 's/^MUSIC_HOST_PATH=//p' "$PILE/.env" | tail -1
}

repond_erreur() {
  repond "{\"chemin\":$(json_chaine "$1"),\"erreur\":$(json_chaine "$2")}"
}

repond() {
  printf '%s' "$1" | dans_le_serveur sh -c 'cat > /app/data/maj/reponse' || true
  # Tant qu'on parcourt, on répond vite : dix secondes par dossier, personne
  # n'attend. L'éveil retombe de lui-même.
  EVEIL=$(( $(date +%s) + 90 ))
}

# ── Changer la racine de la musique ──────────────────────────────────────────
#
# C'est le montage lui-même qui change : réécrire MUSIC_HOST_PATH ne suffit
# pas, il faut remonter la pile pour que Docker refasse le lien.
changer_la_racine() {
  local chemin="$1"
  : > "$TAMPON"

  if [ ! -d "$chemin" ]; then
    dit "« $chemin » n'existe pas sur cette machine."
    dit "fini"
    return
  fi
  if [ ! -r "$chemin" ]; then
    dit "« $chemin » n'est pas lisible : vérifie ses droits."
    dit "fini"
    return
  fi
  if [ ! -f "$PILE/.env" ]; then
    dit "Je ne trouve pas le .env de la pile ($PILE)."
    dit "fini"
    return
  fi

  dit "Nouvelle racine : $chemin"
  # On garde une copie : un .env perdu, c'est un serveur qui ne sait plus
  # parler à sa base.
  cp -p "$PILE/.env" "$PILE/.env.avant-racine" 2>/dev/null || true
  if grep -q '^MUSIC_HOST_PATH=' "$PILE/.env"; then
    local echappe; echappe="$(printf '%s' "$chemin" | sed -e 's/[\/&]/\\&/g')"
    sed -i "s/^MUSIC_HOST_PATH=.*/MUSIC_HOST_PATH=$echappe/" "$PILE/.env"
  else
    printf '\nMUSIC_HOST_PATH=%s\n' "$chemin" >> "$PILE/.env"
  fi

  dit "Remontage du serveur sur le nouveau dossier..."
  if (cd "$PILE" && essaie docker compose -p "$PROJET" up -d --force-recreate app); then
    attendre_le_retour
    dit "Le serveur lit maintenant $chemin."
    dit "Lance une analyse de la bibliothèque pour y retrouver tes titres."
    dit "fini"
  else
    dit "Le remontage a échoué — l'ancien dossier reste en place."
    cp -p "$PILE/.env.avant-racine" "$PILE/.env" 2>/dev/null || true
    raconte_l_echec
  fi
}

# essaie garde la sortie de la commande de côté : un échec sans sa raison
# oblige à aller fouiller le journal du système, c'est-à-dire à ne jamais
# savoir pour qui n'a pas de console.
essaie() { "$@" > "$SORTIE" 2>&1; }

raconte_l_echec() {
  while IFS= read -r ligne; do
    [ -n "$ligne" ] && dit "  $ligne"
  done < <(tail -n 4 "$SORTIE")
  dit "fini"
}

# Le serveur met un moment à répondre après une recréation (yt-dlp se met à
# jour avant Apache). « Le conteneur tourne » ne suffit donc pas : on attend
# qu'il RÉPONDE, sans quoi « fini » s'écrirait sur un serveur encore muet.
attendre_le_retour() {
  for _ in $(seq 1 60); do
    if dans_le_serveur curl -sf -o /dev/null http://localhost/ >/dev/null 2>&1; then
      verifie_les_points
      return 0
    fi
    sleep 5
  done
  return 1
}

# La page d'accueil peut très bien répondre pendant que l'API est morte : le
# 2026-10-01, une erreur de chargement dans un fichier interne a rendu toute
# l'API inutilisable, et la mise à jour s'est dite « finie » sans rien voir.
# On regarde donc quelques points d'entrée : aucun ne doit rendre un 500.
verifie_les_points() {
  local casses=""
  for point in / api/library.php?action=library api/v2/server-info.php \
               get_popular.php get_recent_albums.php; do
    code="$(dans_le_serveur curl -s -o /dev/null -w '%{http_code}' "http://localhost/$point")"
    case "$code" in
      5*) casses="$casses $point" ;;
    esac
  done
  if [ -n "$casses" ]; then
    dit "⚠ Le serveur répond mais son API est en panne :$casses"
    dit "⚠ La version précédente était saine — préviens qui t'a donné celle-ci."
  fi
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
      redemarrer)  redemarrer ;;
      maj)         mettre_a_jour ;;
      lister*)     lister "$(printf '%s' "${demande#lister}" | sed 's/^ *//')" ;;
      racine\ *)   changer_la_racine "${demande#racine }" ;;
    esac
  fi
  # Au repos, dix secondes suffisent : personne ne regarde. Pendant qu'on
  # parcourt les dossiers, en revanche, chaque seconde compte — l'éveil dure
  # une minute et demie après la dernière réponse.
  if [ "$(date +%s)" -lt "$EVEIL" ]; then
    sleep 0.4
  else
    sleep "$INTERVALLE"
  fi
done

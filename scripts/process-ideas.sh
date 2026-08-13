#!/bin/bash
# Traite les idées « confiées à Claude » depuis l'app mobile Gullify.
# Déclenché par cron : si une idée dev_ideas est en statut 'requested',
# lance Claude Code (headless) pour la réaliser de bout en bout, puis la
# marque 'done'. Gaté par le geste de Maxime dans l'app (rien ne part sans
# qu'il ait tapé « Confier à Claude »).
set -uo pipefail

REPO="/home/maxime/gullify"
DB="gullify-db"
LOG="$REPO/logs/process-ideas.log"
LOCK="/tmp/gullify-process-ideas.lock"
AUTH_FLAG="$REPO/logs/ideas-auth-error.flag"
mkdir -p "$REPO/logs"

# Env nécessaire aux builds (cron = env minimal).
export HOME="/home/maxime"
export PATH="$HOME/.local/bin:$HOME/flutter/bin:$HOME/android-sdk/platform-tools:$HOME/android-sdk/cmdline-tools/latest/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export ANDROID_HOME="$HOME/android-sdk"
# Les titres de notification partent d'ici en UTF-8 : sans locale, cron laisse
# LANG vide et les accents arrivent en base en charabia.
export LANG="${LANG:-C.UTF-8}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $*" >> "$LOG"; }

# Verrou : jamais deux traitements en parallèle.
exec 9>"$LOCK"
if ! flock -n 9; then exit 0; fi

# Requête cheap : y a-t-il quelque chose à faire ?
dbq() { docker exec "$DB" sh -lc "mysql --default-character-set=utf8mb4 -uroot -p\"\$MYSQL_ROOT_PASSWORD\" \"\$MYSQL_DATABASE\" -N -e \"$1\"" 2>/dev/null; }

COUNT=$(dbq "SELECT COUNT(*) FROM dev_ideas WHERE status='requested';")
COUNT="${COUNT:-0}"
[ "$COUNT" -eq 0 ] 2>/dev/null && exit 0

cd "$REPO" || { log "cd repo échoué"; exit 1; }

# ── Protection : ne rien lancer si Claude n'est pas authentifié ──────────────
# Le CLI peut se délogger (session expirée) → sinon le cron échouerait en
# silence toutes les 15 min pendant des jours. On vérifie AVANT de toucher
# aux idées, on alerte Maxime dans l'app, et on laisse les idées intactes.
notify_auth_error() {
    # Une alerte non-lue par utilisateur suffit (pas de spam toutes les 15 min).
    for U in $(dbq "SELECT DISTINCT user FROM dev_ideas WHERE status='requested';"); do
        EXISTS=$(dbq "SELECT COUNT(*) FROM notifications WHERE user='$U' AND type='ideas_paused' AND read_at IS NULL;")
        EXISTS="${EXISTS:-0}"
        [ "$EXISTS" -eq 0 ] 2>/dev/null && dbq "INSERT INTO notifications (user, type, title, message) VALUES ('$U', 'ideas_paused', 'Traitement des idees en pause', 'Claude s est deconnecte sur le serveur. Lance claude puis /login pour reprendre le traitement automatique de tes idees.')"
    done
}

# ── Prévenir dans l'app : une idée aboutie donne une notification ───────────
# Le carnet d'idées ne dit rien tant qu'on ne l'ouvre pas ; la cloche de
# l'accueil, elle, se voit. Le texte de l'idée n'est JAMAIS recopié dans le
# shell : c'est le SELECT qui le transporte d'une table à l'autre, donc ni
# apostrophe ni accent ne peut casser la requête.
notify_batch() {
    local ids="${1:-}"
    [ -z "$ids" ] && return 0
    [ "$ids" = "NULL" ] && return 0

    local version
    version=$(grep -E '^version:' "$REPO/app/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1)
    version="${version:-?}"

    dbq "INSERT INTO notifications (user, type, title, message, data)
         SELECT user, 'idea_done', 'Idée réalisée',
                CONCAT(LEFT(text, 400), '\n\nLivré dans la version $version.'),
                JSON_OBJECT('ideaId', id)
         FROM dev_ideas WHERE id IN ($ids) AND status = 'done';"

    dbq "INSERT INTO notifications (user, type, title, message, data)
         SELECT user, 'idea_review', 'Idée à préciser',
                CONCAT(LEFT(text, 400), '\n\nClaude a préféré ne pas la réaliser telle quelle : reformule-la ou découpe-la.'),
                JSON_OBJECT('ideaId', id)
         FROM dev_ideas WHERE id IN ($ids) AND status = 'needs_review';"

    local done_count
    done_count=$(dbq "SELECT COUNT(*) FROM dev_ideas WHERE id IN ($ids) AND status IN ('done','needs_review');")
    log "Notifications envoyées pour ${done_count:-0} idée(s) (version $version)"
}

AUTH_OUT=$(claude -p "Reponds uniquement: OK" --dangerously-skip-permissions 2>&1)
if echo "$AUTH_OUT" | grep -qiE "not logged in|please run /login|/login|unauthenticated|invalid api key"; then
    log "⚠️⚠️  NON AUTHENTIFIÉ — Claude déconnecté. Traitement suspendu."
    log "     → sortie: $(echo "$AUTH_OUT" | head -1)"
    date '+%Y-%m-%d %H:%M:%S  Claude non authentifié (claude /login requis)' > "$AUTH_FLAG"
    notify_auth_error
    exit 0
fi
# Auth OK : on efface le témoin d'erreur s'il traînait.
rm -f "$AUTH_FLAG"

log "=== $COUNT idée(s) confiée(s) → lancement de Claude ==="
# Passe les idées demandées en 'in_progress' (l'app affiche « en cours »).
dbq "UPDATE dev_ideas SET status='in_progress' WHERE status='requested';"
# Le lot de ce passage : c'est sur ces idées-là qu'on notifiera après coup.
BATCH_IDS=$(dbq "SELECT GROUP_CONCAT(id) FROM dev_ideas WHERE status='in_progress';")
BATCH_IDS="${BATCH_IDS:-}"

# ── Pièces jointes (idée #84) ───────────────────────────────────────────────
# Les fichiers joints depuis l'app vivent dans le volume docker (root côté
# hôte) : on les sort dans /tmp pour que Claude puisse les LIRE (captures
# d'écran comprises). Un nom lisible par idée, l'original en sous-dossier.
ATT_DIR="/tmp/gullify-idea-files"
rm -rf "$ATT_DIR"
if [ -n "$BATCH_IDS" ] && [ "$BATCH_IDS" != "NULL" ]; then
    mkdir -p "$ATT_DIR"
    for IID in $(dbq "SELECT DISTINCT idea_id FROM dev_idea_files WHERE idea_id IN ($BATCH_IDS);"); do
        if docker cp "gullify:/app/data/idea_files/$IID" "$ATT_DIR/$IID" >/dev/null 2>&1; then
            log "pièces jointes de l'idée $IID exportées vers $ATT_DIR/$IID"
        else
            log "⚠️  pièces jointes de l'idée $IID introuvables dans le conteneur"
        fi
    done
fi

PROMPT="Tu es Claude Code, invoqué automatiquement sur le serveur de Maxime pour réaliser des idées de développement Gullify qu'il t'a confiées depuis l'app mobile.

Lis les idées à faire :
  docker exec gullify-db sh -lc 'mysql --default-character-set=utf8mb4 -uroot -p\"\$MYSQL_ROOT_PASSWORD\" \"\$MYSQL_DATABASE\" -N -e \"SELECT id, text FROM dev_ideas WHERE status=\\\"in_progress\\\";\"'

Certaines idées portent des pièces jointes (capture de ce qui cloche, maquette, log). Leur inventaire :
  docker exec gullify-db sh -lc 'mysql --default-character-set=utf8mb4 -uroot -p\"\$MYSQL_ROOT_PASSWORD\" \"\$MYSQL_DATABASE\" -N -e \"SELECT idea_id, id, name, mime FROM dev_idea_files WHERE idea_id IN (SELECT id FROM dev_ideas WHERE status=\\\"in_progress\\\");\"'
Les fichiers sont DÉJÀ sortis du conteneur dans /tmp/gullify-idea-files/<idea_id>/<id_du_fichier>.<ext> (l'outil Read affiche les images) : lis-les avant d'implémenter l'idée, ils font partie de la consigne.

Ta mémoire projet (MEMORY.md + gullify-project-context) décrit tout le workflow (Flutter dans app/, build via ./build-app.sh \"changelog\", bump pubspec + appVersion dans settings_screen.dart + entrée changelog.dart, commit/push, docker rebuild si changement serveur PHP/python).

Pour CHAQUE idée en 'in_progress' :
 1. Implémente-la entièrement et proprement (respecte le style existant).
 2. flutter analyze + flutter test doivent passer (mets à jour les goldens si besoin).
 3. Bump de version (pubspec + settings + changelog.dart), ./build-app.sh, commit + push, et rebuild docker UNIQUEMENT si tu as changé du PHP/python.
 4. Marque l'idée 'done' :  ...UPDATE dev_ideas SET status='done' WHERE id=<ID>;
 5. Si une idée est trop ambiguë ou risquée, NE la réalise PAS : marque-la 'needs_review' et passe à la suivante.

Sois rigoureux, prudent, et ne casse rien qui marche. Va au bout."

log "Claude démarre…"
RUN_OUT=$(claude -p "$PROMPT" --dangerously-skip-permissions 2>&1)
RC=$?
echo "$RUN_OUT" >> "$LOG"
log "Claude terminé (code $RC)"

# Si l'auth a expiré EN COURS de run : alerte aussi (post-check).
if echo "$RUN_OUT" | grep -qiE "not logged in|please run /login|unauthenticated|invalid api key"; then
    log "⚠️⚠️  Déconnexion pendant le traitement."
    date '+%Y-%m-%d %H:%M:%S  Claude déconnecté pendant le run' > "$AUTH_FLAG"
    notify_auth_error
fi

# Idées abouties → notification dans l'app (avant le filet : une idée remise
# en file n'a rien à annoncer).
notify_batch "$BATCH_IDS"

# Filet : toute idée restée 'in_progress' (Claude n'a pas fini/planté) est
# remise en 'requested' pour un prochain passage.
dbq "UPDATE dev_ideas SET status='requested' WHERE status='in_progress';"
log "=== fin ==="

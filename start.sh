#!/bin/bash
if [ ! -z "$PUID" ]; then
  echo "Setting www-data UID to $PUID..."
  usermod -u $PUID www-data
fi
if [ ! -z "$PGID" ]; then
  echo "Setting www-data GID to $PGID..."
  groupmod -g $PGID www-data
fi
echo "Fixing script permissions and line endings..."
dos2unix /app/scripts/*.php /app/scripts/*.sh 2>/dev/null
chmod 755 /app/scripts/*.sh /app/scripts/*.php
echo "Ensuring ownership of data and music folders..."
if [ ! -f /app/.env ]; then
  echo "No .env found, copying from .env.example..."
  cp /app/.env.example /app/.env
fi
chown www-data:www-data /app/.env
chown -R www-data:www-data /app/data /music

# yt-dlp est installé dans une couche Docker mise en cache : sans ces lignes,
# ni un redémarrage ni un `build` rapide ne le rafraîchissaient — seul
# `update.sh` option 2 (rebuild sans cache) le faisait, ce que personne ne
# devine quand les téléchargements se mettent à échouer. Or YouTube casse
# yt-dlp régulièrement et le correctif arrive par une nouvelle version. On met
# donc à jour au démarrage, avant apache pour qu'aucun téléchargement ne parte
# pendant le remplacement des fichiers. Best-effort : hors ligne ou PyPI en
# panne, on repart sur la version déjà installée.
if [ "${YTDLP_AUTO_UPDATE:-1}" != "0" ] && [ -x /opt/ytdlp/bin/pip ]; then
  echo "Updating yt-dlp (set YTDLP_AUTO_UPDATE=0 to skip)..."
  if timeout 180 /opt/ytdlp/bin/pip install -q -U --timeout 15 --retries 1 yt-dlp; then
    echo "yt-dlp is now $(/opt/ytdlp/bin/yt-dlp --version 2>/dev/null)"
  else
    echo "yt-dlp update skipped, keeping $(/opt/ytdlp/bin/yt-dlp --version 2>/dev/null)"
  fi
fi

echo "Starting services..."
cron
exec apache2-foreground

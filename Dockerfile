FROM php:8.2-apache

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev libjpeg-dev libfreetype6-dev \
    python3 python3-pip python3-venv ffmpeg curl cron unzip dos2unix \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions (gd, pdo_mysql, mysqli - others are already bundled)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd pdo pdo_mysql mysqli

# Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Python tools (use venv to avoid --break-system-packages issues)
RUN python3 -m venv /opt/ytdlp \
    && /opt/ytdlp/bin/pip install yt-dlp ytmusicapi musicxmatch-api \
    && ln -s /opt/ytdlp/bin/yt-dlp /usr/local/bin/yt-dlp \
    && ln -s /opt/ytdlp/bin/python3 /usr/local/bin/python3-venv

# Apache rewrite module
RUN a2enmod rewrite

WORKDIR /app
ARG CACHEBUST=1
COPY . /app/

# Fix CRLF and permissions
RUN dos2unix /app/scripts/*.php /app/scripts/*.sh \
    && chmod +x /app/scripts/*.php /app/scripts/*.sh

# Install PHP dependencies (phpseclib, etc.) — preserves vendor/getid3 placed manually
RUN cd /app && composer install --no-dev --no-interaction --no-progress --optimize-autoloader

# Apache config: DocumentRoot = /app/public
RUN sed -i 's|/var/www/html|/app/public|g' /etc/apache2/sites-available/000-default.conf \
    && printf '<Directory /app/public>\n  AllowOverride All\n  Require all granted\n</Directory>\n' \
    >> /etc/apache2/apache2.conf

# php.ini overrides
RUN printf "upload_max_filesize=50M\npost_max_size=50M\nmemory_limit=256M\nmax_execution_time=3600\n" \
    > /usr/local/etc/php/conf.d/gullify.ini

# Data directories
RUN mkdir -p /app/data/cache /app/data/logs /app/data/downloads \
    && chown -R www-data:www-data /app/data

# Make scripts executable and readable by www-data
RUN chmod 755 /app/scripts/*.sh /app/scripts/*.php

# Cron job for download queue processing
# NOTE: cron.d files MUST end with a newline, and need PATH for yt-dlp/php
RUN printf 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n* * * * * www-data /app/scripts/process-queue.sh >> /app/data/logs/queue.log 2>&1\n' \
    > /etc/cron.d/gullify-queue \
    && chmod 0644 /etc/cron.d/gullify-queue

# Startup script: fix permissions, line endings, start cron, then apache
RUN printf '#!/bin/bash\n\
if [ ! -z "$PUID" ]; then\n\
  echo "Setting www-data UID to $PUID..."\n\
  usermod -u $PUID www-data\n\
fi\n\
if [ ! -z "$PGID" ]; then\n\
  echo "Setting www-data GID to $PGID..."\n\
  groupmod -g $PGID www-data\n\
fi\n\
echo "Fixing script permissions and line endings..."\n\
dos2unix /app/scripts/*.php /app/scripts/*.sh 2>/dev/null\n\
chmod 755 /app/scripts/*.sh /app/scripts/*.php\n\
echo "Ensuring ownership of data and music folders..."\n\
if [ ! -f /app/.env ]; then\n\
  echo "No .env found, copying from .env.example..."\n\
  cp /app/.env.example /app/.env\n\
fi\n\
chown www-data:www-data /app/.env\n\
chown -R www-data:www-data /app/data /music\n\
echo "Starting services..."\n\
cron\n\
exec apache2-foreground\n' > /app/start.sh \
    && chmod +x /app/start.sh

EXPOSE 80
HEALTHCHECK --interval=30s CMD curl -sf http://localhost/ || exit 1
CMD ["/app/start.sh"]

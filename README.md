# Gullify

Self-hosted music streaming server with a YouTube Music-style interface.

## Quick Start (Docker)

1. Clone the repository:
   ```bash
   git clone https://github.com/gullify/gullify.git
   cd gullify
   ```

2. Edit `docker-compose.yml` — set your music directory path:
   ```yaml
   volumes:
     - /path/to/your/music:/music:ro
   ```

3. Copy the environment file:
   ```bash
   cp .env.example .env
   ```

4. Start the containers:
   ```bash
   docker-compose up -d
   ```

5. Open http://localhost:8080 and follow the setup wizard.

## Features

- Stream your personal music collection
- YouTube Music-inspired interface with Liquid Glass design
- Multi-user support (family sharing)
- Favorites, playlists, play statistics
- Album artwork extraction from ID3 tags and filesystem
- Radio mode with weighted random playback
- Web radio stations (Canadian stations built-in)
- YouTube album downloads via yt-dlp
- ID3 tag editing (single and batch)
- Lyrics display (embedded + Musixmatch)
- Artist news feed
- Music suggestions by genre
- PWA — installable on mobile
- Dark mode

## Music Organization

```
/music/
  username_folder/
    Artist/
      Album/
        01 - Track.mp3
```

Supported formats: MP3, FLAC, M4A, OGG, WAV, AAC, WMA, OPUS, AIFF

## Manual Installation (without Docker)

### Requirements

- PHP >= 8.0 with extensions: PDO, pdo_mysql, fileinfo, GD, curl, mbstring
- MySQL 8.0+
- Apache with mod_rewrite
- Python 3 with yt-dlp (optional, for downloads)

### Steps

1. Point your Apache DocumentRoot to the `public/` directory
2. Copy `.env.example` to `.env` and configure your MySQL credentials
3. Open the app in your browser — the setup wizard will guide you through the rest

## Configuration

All configuration is managed through the `.env` file:

| Variable | Description | Default |
|---|---|---|
| `MYSQL_HOST` | MySQL server host | `db` |
| `MYSQL_PORT` | MySQL server port | `3306` |
| `MYSQL_DATABASE` | Database name | `gullify` |
| `MYSQL_USER` | Database user | `gullify` |
| `MYSQL_PASSWORD` | Database password | `changeme` |
| `MUSIC_BASE_PATH` | Path to music files | `/music` |
| `DATA_PATH` | Path for cache/logs/downloads | `/app/data` |
| `APP_URL` | Public URL of the app | `http://localhost:8080` |

## CLI Scripts

```bash
# Full library scan
php scripts/scan-library.php

# Scan specific user
php scripts/scan-library.php username

# Scan without artwork (faster)
php scripts/scan-library.php --skip-artwork

# Genre scanning
php scripts/scan-genres.php
```

## License

MIT

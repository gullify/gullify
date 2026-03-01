# Gullify

Self-hosted music streaming server with a YouTube Music-style interface.

## Quick Start (Docker)

1. Clone the repository:
   ```bash
   git clone https://github.com/gullify/gullify.git
   cd gullify
   ```

2. Edit `docker compose.yml` — set your music directory path:
   ```yaml
   volumes:
     - /path/to/your/music:/music:ro
   ```

3. Copy and configure the environment file:
   ```bash
   cp .env.example .env
   ```
   Edit `.env` and set at minimum:
   - `APP_DOMAIN` — your domain (e.g. `music.example.com`)
   - `APP_URL` — your full URL (e.g. `https://music.example.com`)
   - `MYSQL_PASSWORD` / `MYSQL_ROOT_PASSWORD` — strong passwords
   - `APP_SECRET` — a long random string
   - `MUSIC_HOST_PATH` — path to your music on the host

4. Point your domain's DNS to your server's IP, then start:
   ```bash
   docker compose up -d
   ```
   Caddy will automatically obtain a Let's Encrypt SSL certificate for your domain. Ports 80 and 443 must be open on your firewall.

5. Open `https://your-domain.com` and follow the setup wizard.

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

## API Reference

Gullify exposes a REST API for building clients (mobile apps, Android Auto, etc.). All responses are JSON.

### Authentication

```http
POST /api/login.php
Content-Type: application/json

{"username": "alice", "password": "secret"}
```

```json
{"token": "abc123...", "username": "alice", "user_id": 1}
```

Use the token as a Bearer token for subsequent requests:
```http
Authorization: Bearer abc123...
```

---

### Library — `GET /api/library.php`

| Action | Parameters | Description |
|--------|-----------|-------------|
| `library` (default) | `user`, `limit`, `offset` | Paginated list of artists |
| `artist` | `user`, `id` | Artist details + albums |
| `album` | `user`, `id` | Album details + songs |
| `search` | `user`, `q` | Search songs, artists, albums |
| `get_all_albums` | `user`, `limit`, `offset`, `sort`, `search` | Paginated albums |
| `recent_albums` | `user`, `days` | Recently added albums |
| `get_genres` | `user` | All genres with counts |
| `get_artists_by_genre` | `user`, `genre` | Artists filtered by genre |
| `get_stats` | `user` | Full listening statistics |
| `get_favorites` | `user` | Favorited song IDs |
| `get_all_favorites` | `user` | Favorite songs, artists, albums |
| `toggle_favorite` | `user`, `song_id` | Add/remove song favorite |
| `toggle_favorite_artist` | `user`, `artist_id` | Add/remove artist favorite |
| `toggle_favorite_album` | `user`, `album_id` | Add/remove album favorite |
| `get_favorite_artists` | `user` | All favorite artists |
| `get_favorite_albums` | `user` | All favorite albums |
| `get_playlists` | `user` | All user playlists |
| `get_playlist_songs` | `user`, `playlist_id` | Songs in a playlist |
| `create_playlist` | `user`, `name` | Create playlist |
| `rename_playlist` | `user`, `playlist_id`, `name` | Rename playlist |
| `delete_playlist` | `user`, `playlist_id` | Delete playlist |
| `add_to_playlist` | `user`, `playlist_id`, `song_id` | Add song to playlist |
| `remove_from_playlist` | `user`, `playlist_song_id` | Remove song from playlist |
| `song_properties` | `user`, `song_id` | Detailed file info |
| `get_users` | — | List active users |

**Artist response example:**
```json
{
  "error": false,
  "data": {
    "artist": {"id": 1, "name": "Metallica", "imageUrl": "/serve_image.php?artist_id=1", "genre": "Metal"},
    "albums": [
      {"id": 5, "name": "Black Album", "year": 1991, "artworkUrl": "/serve_image.php?album_id=5", "songCount": 12}
    ]
  }
}
```

---

### Scanning — `GET /api/scan.php`

| Action | Parameters | Description |
|--------|-----------|-------------|
| `force_scan` | `user` (optional) | Full library rescan |
| `fast_scan` | `user` (optional) | Scan without artwork |
| `artwork_scan` | `user` (required) | Scan artwork only |
| `scan_status` | — | Current scan progress |
| `genre_scan` | `user` (optional) | Auto-assign genres |
| `genre_scan_status` | — | Genre scan progress |
| `set_artist_genre` | `artist_id`, `genre` | Set genre manually |
| `track_play` | `song_id`, `user`, `duration`, `completed` | Record a play event |
| `get_top_songs` | `user`, `limit` | Most played songs |
| `get_recent_plays` | `user`, `limit` | Recently played songs |
| `get_playlists` | `user` | User playlists |
| `create_playlist` | `user`, `name` | Create playlist |
| `toggle_favorite` | `user`, `song_id` | Toggle song favorite |
| `toggle_favorite_artist` | `user`, `artist_id` | Toggle artist favorite |
| `toggle_favorite_album` | `user`, `album_id` | Toggle album favorite |
| `get_all_favorites` | `user` | All favorites |

**Scan status response:**
```json
{
  "success": true,
  "data": {
    "scanning": true,
    "progress": {"status": "Scanning...", "processed": 120, "total": 300, "percent": 40, "current_artist": "Radiohead"},
    "last_update_formatted": "2026-01-01 12:00:00"
  }
}
```

---

### Radio — `GET /api/radio.php`

| Action | Parameters | Description |
|--------|-----------|-------------|
| `get_random` (default) | `user`, `genre`, `limit` | Random songs for radio |
| `track_play` | `song_id`, `user`, `duration`, `completed` | Record play |
| `get_stats` | `song_id` | Play stats for a song |

```bash
GET /api/radio.php?user=alice&genre=Rock&limit=20
```

---

### Web Radio — `GET /api/web-radio.php`

| Action | Parameters | Description |
|--------|-----------|-------------|
| `list` (default) | — | Canadian radio stations |
| `search` | `q` | Search by name/genre |
| `refresh` | — | Force cache refresh |
| `genres` | — | List all genres |

**Station object:**
```json
{
  "id": "abc123",
  "name": "CKAC Montreal",
  "state": "Quebec",
  "language": "French",
  "genres": ["Pop", "Rock"],
  "streams": [{"url": "https://...", "format": "MP3", "bitrate": 128}],
  "logo": "https://..."
}
```

---

### Downloads — `GET /api/download.php`

| Action | Parameters | Description |
|--------|-----------|-------------|
| `start` | `url`, `user`, `artist_id`, `artist_name`, `album_name` | Start YouTube download |
| `status` | `download_id` | Download progress |
| `list` | `user` | All downloads |
| `cancel` | `download_id` | Cancel download |
| `retry` | `download_id` | Retry failed download |

**Download status values:** `queued` · `downloading` · `completed` · `error` · `cancelled`

---

### Streaming — `GET /stream.php`

```http
GET /stream.php?path=Artist/Album/01%20-%20Track.mp3
Range: bytes=0-100000
```

- Returns HTTP 206 with `Content-Range` for seeking
- Supports: MP3, FLAC, M4A, OGG, WAV, AAC, WMA, OPUS, AIFF

---

### Images — `GET /serve_image.php`

```http
GET /serve_image.php?album_id=5
GET /serve_image.php?artist_id=1
```

Returns JPEG/PNG image. Falls back to placeholder if not found. Supports `304 Not Modified` for caching.

---

### Lyrics — `GET /get_lyrics.php`

```http
GET /get_lyrics.php?path=Artist/Album/Track.mp3
```

```json
{"success": true, "lyrics": "...", "source": "id3 | lrclib | musixmatch"}
```

---

### Admin — `POST /api/admin.php` *(requires admin session)*

| Action | Description |
|--------|-------------|
| `list_users` | Get all users |
| `create_user` | Create user (`username`, `password`, `full_name`, `music_directory`, `storage_type`) |
| `delete_user` | Delete user (`user_id`) |
| `toggle_active` | Enable/disable user (`user_id`) |
| `update_password` | Change password (`user_id`, `password`) |
| `update_directory` | Set music directory (`user_id`, `music_directory`) |
| `toggle_admin` | Toggle admin status (`user_id`) |
| `update_sftp` | Configure SFTP storage (`user_id`, `sftp_host`, `sftp_user`, etc.) |
| `test_sftp_connection` | Test SFTP credentials |
| `list_directories` | List available music directories |

---

### Common Response Format

```json
{"success": true, "data": {...}}
{"success": false, "error": "Error description"}
```

HTTP status codes: `200` OK · `206` Partial (streaming) · `400` Bad request · `401` Unauthorized · `403` Forbidden · `404` Not found · `500` Server error

## License

MIT

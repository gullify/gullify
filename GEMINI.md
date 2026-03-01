# GEMINI.md - Gullify Music Streamer

## Project Overview

This project, named Gullify, is a self-hosted music streaming server written in PHP. It provides a web interface inspired by YouTube Music to browse and play a personal music collection. The application is designed to be multi-user and supports individual music libraries for each user.

The frontend is a single-page application (SPA) built with vanilla JavaScript, which communicates with a PHP backend through a RESTful API. The backend handles library management, user authentication, and media streaming. The entire application is containerized using Docker, with Caddy as the web server, a PHP-FPM service, and a MySQL database.

### Key Features:

*   YouTube Music-style UI with a dark mode.
*   Multi-user support with per-user libraries.
*   Music library organized by artists, albums, and songs.
*   Features like favorites, playlists, and listening statistics.
*   Automatic artwork extraction and a background scanner for the music library.
*   Support for multiple storage backends, including local filesystem and SFTP.
*   ID3 tag editing and lyrics fetching.
*   PWA (Progressive Web App) support for a native-like experience on mobile.

### Technologies Used:

*   **Backend:** PHP 8.1+
*   **Frontend:** Vanilla JavaScript, HTML, CSS
*   **Database:** MySQL 8.0
*   **Web Server:** Caddy
*   **Containerization:** Docker, Docker Compose

## Building and Running

The project is designed to be run with Docker.

### Setup & Running with Docker:

1.  **Environment Configuration:** Copy the `.env.example` file to `.env` and customize it. At a minimum, you should set a password for `MYSQL_PASSWORD` and `MYSQL_ROOT_PASSWORD`.
    ```bash
    cp .env.example .env
    ```

2.  **Music Directory:** In `docker-compose.yml`, modify the volume mapping for the `app` service to point to your music library on the host machine.
    ```yaml
    # in docker-compose.yml
    services:
      app:
        volumes:
          - /path/to/your/music:/music # <-- CHANGE THIS
          # ...
    ```

3.  **Build and Start:** Use Docker Compose to build and start all the services.
    ```bash
    docker-compose up -d --build
    ```
    The web application will be available at `http://localhost` (or the port you configured). The first time you access it, a setup wizard will guide you through creating an admin account and configuring your library.

### CLI Scripts:

The project includes several command-line scripts for maintenance, which should be run inside the `app` container:

*   **Full Library Scan:**
    ```bash
    docker-compose exec app php scripts/scan-library.php <username>
    ```
*   **Genre Scan:**
    ```bash
    docker-compose exec app php scripts/scan-genres.php <username>
    ```
*   **Artwork Scan:**
    ```bash
    docker-compose exec app php scripts/scan-artwork.php <username>
    ```

## Development Conventions

*   **Configuration:** All configuration is managed via the `.env` file and accessed through the `AppConfig` class (`src/AppConfig.php`). Do not use hardcoded credentials or paths.
*   **Database:** Database interactions are performed using the PDO extension. The connection is obtained via `AppConfig::getDB()`. The database schema is defined in `setup/schema.sql`. Simple migrations are handled automatically by the `AppConfig` class.
*   **Backend API:** The main API logic is split across several files in the `public/` directory (e.g., `api-mysql.php`, `get_library_mysql.php`). These files handle requests from the frontend, interact with the database, and return JSON responses.
*   **Frontend:** The frontend is a single `index.php` file containing the HTML structure. All dynamic behavior, UI rendering, and API communication are handled by JavaScript within `<script>` tags in `index.php`.
*   **Authentication:** Authentication is required for most of the application and is handled by `src/auth_required.php`. User and session management logic is in `src/Auth.php`.
*   **Storage:** The application supports different storage backends for music files (local, SFTP) through a `StorageInterface` located in `src/Storage/`. The factory pattern (`StorageFactory`) is used to instantiate the correct storage driver based on user settings.

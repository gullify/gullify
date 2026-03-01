-- Gullify Music Streaming - Complete MySQL Schema
-- Generated for setup wizard

-- Users
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    is_active TINYINT(1) DEFAULT 1,
    is_admin TINYINT(1) DEFAULT 0,
    music_directory VARCHAR(255),
    storage_type ENUM('local', 'sftp') DEFAULT 'local',
    sftp_host VARCHAR(255) NULL,
    sftp_port SMALLINT UNSIGNED DEFAULT 22,
    sftp_user VARCHAR(100) NULL,
    sftp_password VARCHAR(512) NULL,  -- AES-256-CBC encrypted
    sftp_path VARCHAR(255) NULL,       -- Remote base path
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Sessions
CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(128) PRIMARY KEY,
    user_id INT NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_activity DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Library status
CREATE TABLE IF NOT EXISTS library_status (
    id INT AUTO_INCREMENT PRIMARY KEY,
    last_update INT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Artists
CREATE TABLE IF NOT EXISTS artists (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    user VARCHAR(50) NOT NULL,
    image LONGTEXT,
    album_count INT DEFAULT 0,
    song_count INT DEFAULT 0,
    genre VARCHAR(100) NULL,
    INDEX idx_artists_user (user),
    INDEX idx_artists_name (name),
    INDEX idx_artists_genre (genre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Albums
CREATE TABLE IF NOT EXISTS albums (
    id INT AUTO_INCREMENT PRIMARY KEY,
    artist_id INT NOT NULL,
    name VARCHAR(255) NOT NULL,
    year INT NULL,
    artwork LONGTEXT,
    genre VARCHAR(100) NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_albums_artist (artist_id),
    INDEX idx_albums_genre (genre),
    FOREIGN KEY (artist_id) REFERENCES artists(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Songs
CREATE TABLE IF NOT EXISTS songs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    album_id INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    track_number INT DEFAULT 0,
    duration INT DEFAULT 0,
    file_path VARCHAR(500) NOT NULL,
    file_hash VARCHAR(32),
    genre VARCHAR(100) NULL,
    INDEX idx_songs_album (album_id),
    INDEX idx_songs_filepath (file_path),
    FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Library stats (snapshots)
CREATE TABLE IF NOT EXISTS library_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user VARCHAR(50) NOT NULL,
    artist_count INT DEFAULT 0,
    album_count INT DEFAULT 0,
    song_count INT DEFAULT 0,
    recorded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_library_stats_user (user)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Song statistics
CREATE TABLE IF NOT EXISTS song_stats (
    song_id INT PRIMARY KEY,
    play_count INT DEFAULT 0,
    first_played_at DATETIME,
    last_played_at DATETIME,
    total_play_time INT DEFAULT 0,
    skip_count INT DEFAULT 0,
    FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Play history
CREATE TABLE IF NOT EXISTS play_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    song_id INT NOT NULL,
    user VARCHAR(50) NOT NULL,
    played_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    play_duration INT DEFAULT 0,
    completed TINYINT(1) DEFAULT 0,
    source VARCHAR(20) DEFAULT 'player',
    INDEX idx_play_history_user (user),
    INDEX idx_play_history_song (song_id),
    INDEX idx_play_history_date (played_at),
    FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Favorites (songs)
CREATE TABLE IF NOT EXISTS favorites (
    id INT AUTO_INCREMENT PRIMARY KEY,
    song_id INT NOT NULL,
    user VARCHAR(50) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_favorite (song_id, user),
    INDEX idx_favorites_user (user),
    FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Favorite artists
CREATE TABLE IF NOT EXISTS favorite_artists (
    id INT AUTO_INCREMENT PRIMARY KEY,
    artist_id INT NOT NULL,
    user VARCHAR(50) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_fav_artist (artist_id, user),
    INDEX idx_fav_artists_user (user),
    FOREIGN KEY (artist_id) REFERENCES artists(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Favorite albums
CREATE TABLE IF NOT EXISTS favorite_albums (
    id INT AUTO_INCREMENT PRIMARY KEY,
    album_id INT NOT NULL,
    user VARCHAR(50) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_fav_album (album_id, user),
    INDEX idx_fav_albums_user (user),
    FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Playlists
CREATE TABLE IF NOT EXISTS playlists (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    user VARCHAR(50) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_playlists_user (user)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Playlist songs
CREATE TABLE IF NOT EXISTS playlist_songs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    playlist_id INT NOT NULL,
    song_id INT NOT NULL,
    track_order INT DEFAULT 0,
    UNIQUE KEY unique_playlist_song (playlist_id, song_id),
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
    FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Genres taxonomy
CREATE TABLE IF NOT EXISTS genres (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    parent_id INT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (parent_id) REFERENCES genres(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Default genre seed data (only inserted if table is empty)
INSERT INTO genres (name, parent_id)
SELECT name, NULL FROM (
    SELECT 'Alternatif'            UNION ALL
    SELECT 'Blues'                 UNION ALL
    SELECT 'Musique pour enfants'  UNION ALL
    SELECT 'Classique'             UNION ALL
    SELECT 'Humoristique'          UNION ALL
    SELECT 'Country'               UNION ALL
    SELECT 'Dance'                 UNION ALL
    SELECT 'Électronique'          UNION ALL
    SELECT 'Folk'                  UNION ALL
    SELECT 'Français'              UNION ALL
    SELECT 'Hip-Hop'               UNION ALL
    SELECT 'Instrumental'          UNION ALL
    SELECT 'Jazz'                  UNION ALL
    SELECT 'Métal'                 UNION ALL
    SELECT 'Pop'                   UNION ALL
    SELECT 'R&B'                   UNION ALL
    SELECT 'Reggae'                UNION ALL
    SELECT 'Ska'                   UNION ALL
    SELECT 'Rock'                  UNION ALL
    SELECT 'Punk Rock'             UNION ALL
    SELECT 'Trame sonore'          UNION ALL
    SELECT 'Îles-de-la-Madeleine'  UNION ALL
    SELECT 'Contes'                UNION ALL
    SELECT 'Québecois'             UNION ALL
    SELECT 'Acadien'
) AS g(name)
WHERE (SELECT COUNT(*) FROM genres) = 0;

-- Views
CREATE OR REPLACE VIEW top_songs AS
    SELECT s.id as song_id, s.title, a.name as artist, al.name as album,
           ss.play_count, ss.last_played_at, ss.total_play_time
    FROM song_stats ss
    JOIN songs s ON ss.song_id = s.id
    JOIN albums al ON s.album_id = al.id
    JOIN artists a ON al.artist_id = a.id
    ORDER BY ss.play_count DESC;

CREATE OR REPLACE VIEW recent_plays AS
    SELECT ph.id, ph.song_id, s.title, a.name as artist, al.name as album,
           ph.user, ph.played_at, ph.play_duration, ph.completed, ph.source
    FROM play_history ph
    JOIN songs s ON ph.song_id = s.id
    JOIN albums al ON s.album_id = al.id
    JOIN artists a ON al.artist_id = a.id
    ORDER BY ph.played_at DESC;

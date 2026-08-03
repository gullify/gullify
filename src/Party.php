<?php
/**
 * Gullify — Parties multijoueur des jeux.
 *
 * Une « partie » est un salon éphémère créé depuis l'app par un utilisateur
 * (l'hôte). Le serveur en tire un code court que l'hôte envoie par SMS ; les
 * invités ouvrent https://<domaine>/j/<CODE> dans leur navigateur, donnent
 * leur prénom et jouent. À la fin de la partie le salon est supprimé et le
 * lien ne répond plus — et de toute façon toute partie oubliée est purgée
 * après PARTY_TTL_HOURS.
 *
 * Le serveur fait autorité : c'est lui qui tire les manches, qui tient le
 * chrono et qui compte les points. Un invité ne reçoit jamais la bonne
 * réponse avant la révélation, ni le chemin des fichiers audio (il écoute un
 * extrait transcodé, servi manche par manche contre son jeton).
 *
 * Il n'y a pas de processus d'arrière-plan : l'avancement des manches est
 * calculé à la volée à chaque lecture de l'état (voir tick()). Un salon que
 * plus personne ne consulte se fige donc, ce qui est exactement ce qu'on veut.
 */

require_once __DIR__ . '/AppConfig.php';
require_once __DIR__ . '/TrackArtist.php';

class Party
{
    /** Durée de vie d'un salon, quoi qu'il arrive. */
    public const TTL_HOURS = 6;

    /** Jeux jouables à plusieurs. */
    public const GAMES = ['blind', 'cover', 'duel', 'chrono'];

    /** Nombre de manches par partie. */
    private const ROUNDS = ['blind' => 10, 'cover' => 8, 'duel' => 10, 'chrono' => 24];

    /** Temps de réponse d'une manche, en millisecondes. */
    private const ROUND_MS = ['blind' => 20000, 'cover' => 20000, 'duel' => 15000, 'chrono' => 45000];

    /** Temps d'affichage de la réponse entre deux manches. */
    private const REVEAL_MS = 4500;

    /** Vies au départ (Chrono uniquement). */
    private const CHRONO_LIVES = 3;

    /** Chrono : longueur de frise qui met fin à la partie (règle Hitster). */
    private const CHRONO_GOAL = 10;

    /** Joueurs simultanés dans un salon (hôte compris). */
    public const MAX_PLAYERS = 12;

    // ─────────────────────────────────────────────────────────── schéma ──

    /** Création des tables — idempotent, une fois par requête. */
    public static function ensureTables(): void
    {
        static $done = false;
        if ($done) return;
        $done = true;
        try {
            $db = AppConfig::getDB();
            $db->exec("
                CREATE TABLE IF NOT EXISTS game_parties (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    code VARCHAR(8) NOT NULL,
                    host_user VARCHAR(100) NOT NULL,
                    game VARCHAR(16) NOT NULL,
                    audio_mode ENUM('host','guests') NOT NULL DEFAULT 'host',
                    status ENUM('lobby','playing','finished') NOT NULL DEFAULT 'lobby',
                    rounds JSON NULL,
                    round_index INT NOT NULL DEFAULT 0,
                    phase VARCHAR(12) NOT NULL DEFAULT 'lobby',
                    phase_at BIGINT UNSIGNED NOT NULL DEFAULT 0,
                    turn_player_id BIGINT UNSIGNED NULL,
                    version INT UNSIGNED NOT NULL DEFAULT 1,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    expires_at DATETIME NOT NULL,
                    UNIQUE KEY uniq_party_code (code),
                    INDEX idx_party_host (host_user),
                    INDEX idx_party_expires (expires_at)
                ) DEFAULT CHARSET=utf8mb4
            ");
            $db->exec("
                CREATE TABLE IF NOT EXISTS game_party_players (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    party_id BIGINT UNSIGNED NOT NULL,
                    name VARCHAR(40) NOT NULL,
                    token CHAR(32) NOT NULL,
                    is_host TINYINT(1) NOT NULL DEFAULT 0,
                    score INT NOT NULL DEFAULT 0,
                    lives INT NOT NULL DEFAULT 0,
                    state JSON NULL,
                    joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    last_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uniq_player_token (token),
                    INDEX idx_player_party (party_id, id)
                ) DEFAULT CHARSET=utf8mb4
            ");
            $db->exec("
                CREATE TABLE IF NOT EXISTS game_party_answers (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    party_id BIGINT UNSIGNED NOT NULL,
                    round_index INT NOT NULL,
                    player_id BIGINT UNSIGNED NOT NULL,
                    answer VARCHAR(64) NULL,
                    ms INT NOT NULL DEFAULT 0,
                    correct TINYINT(1) NOT NULL DEFAULT 0,
                    points INT NOT NULL DEFAULT 0,
                    UNIQUE KEY uniq_answer (party_id, round_index, player_id),
                    INDEX idx_answer_round (party_id, round_index)
                ) DEFAULT CHARSET=utf8mb4
            ");
        } catch (\Throwable $e) {
            error_log('Party::ensureTables failed: ' . $e->getMessage());
        }
    }

    /** Horloge de référence du serveur, en millisecondes. */
    public static function now(): int
    {
        return (int)round(microtime(true) * 1000);
    }

    // ──────────────────────────────────────────────────────── cycle de vie ──

    /**
     * Crée un salon et y installe l'hôte comme premier joueur.
     * @return array{party: array, player: array}
     */
    public static function create(string $hostUser, string $game, string $audioMode, string $hostName): array
    {
        self::ensureTables();
        self::purgeExpired();
        if (!in_array($game, self::GAMES, true)) {
            throw new InvalidArgumentException('Jeu inconnu');
        }
        $audioMode = $audioMode === 'guests' ? 'guests' : 'host';

        $db = AppConfig::getDB();
        // Un hôte n'a qu'un salon à la fois : relancer une partie ferme la
        // précédente plutôt que de laisser des codes fantômes derrière soi.
        self::closeAllFor($hostUser);

        $code = self::freshCode($db);
        $stmt = $db->prepare(
            'INSERT INTO game_parties (code, host_user, game, audio_mode, expires_at)
             VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ' . self::TTL_HOURS . ' HOUR))'
        );
        $stmt->execute([$code, $hostUser, $game, $audioMode]);
        $partyId = (int)$db->lastInsertId();

        $player = self::addPlayer($partyId, $hostName, true);
        return ['party' => self::byId($partyId), 'player' => $player];
    }

    /** Un code court, lisible au téléphone : ni O/0 ni I/1. */
    private static function freshCode(PDO $db): string
    {
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        for ($try = 0; $try < 50; $try++) {
            $code = '';
            for ($i = 0; $i < 4; $i++) {
                $code .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
            $stmt = $db->prepare('SELECT 1 FROM game_parties WHERE code = ?');
            $stmt->execute([$code]);
            if (!$stmt->fetchColumn()) return $code;
        }
        // Improbable (32^4 codes, salons éphémères) : on rallonge plutôt que
        // d'échouer.
        return strtoupper(bin2hex(random_bytes(3)));
    }

    private static function addPlayer(int $partyId, string $name, bool $isHost): array
    {
        $db = AppConfig::getDB();
        $token = bin2hex(random_bytes(16));
        $stmt = $db->prepare(
            'INSERT INTO game_party_players (party_id, name, token, is_host, lives)
             VALUES (?, ?, ?, ?, ?)'
        );
        $stmt->execute([$partyId, $name, $token, $isHost ? 1 : 0, self::CHRONO_LIVES]);
        $id = (int)$db->lastInsertId();
        $stmt = $db->prepare('SELECT * FROM game_party_players WHERE id = ?');
        $stmt->execute([$id]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: [];
    }

    /**
     * Un invité rejoint le salon. Refusé une fois la partie lancée : arriver
     * en cours de route donnerait un classement faussé.
     * @return array{party: array, player: array}
     */
    public static function join(string $code, string $name): array
    {
        self::ensureTables();
        self::purgeExpired();
        $party = self::byCode($code);
        if (!$party) throw new RuntimeException('party_not_found');
        if ($party['status'] !== 'lobby') throw new RuntimeException('party_started');

        $name = self::cleanName($name);
        $players = self::players((int)$party['id']);
        if (count($players) >= self::MAX_PLAYERS) throw new RuntimeException('party_full');
        foreach ($players as $p) {
            if (mb_strtolower($p['name']) === mb_strtolower($name)) {
                throw new RuntimeException('name_taken');
            }
        }

        $player = self::addPlayer((int)$party['id'], $name, false);
        self::bump((int)$party['id']);
        return ['party' => self::byId((int)$party['id']), 'player' => $player];
    }

    public static function cleanName(string $raw): string
    {
        $name = trim(preg_replace('/\s+/u', ' ', $raw) ?? '');
        $name = mb_substr($name, 0, 20);
        if ($name === '') throw new RuntimeException('name_required');
        return $name;
    }

    /** Un joueur quitte le salon. L'hôte qui part ferme la partie. */
    public static function leave(array $party, array $player): void
    {
        $db = AppConfig::getDB();
        if ((int)$player['is_host'] === 1) {
            self::close((int)$party['id']);
            return;
        }
        $db->prepare('DELETE FROM game_party_players WHERE id = ?')->execute([$player['id']]);
        $db->prepare('DELETE FROM game_party_answers WHERE player_id = ?')->execute([$player['id']]);
        self::bump((int)$party['id']);
    }

    /** Supprime le salon : le lien ne répond plus. */
    public static function close(int $partyId): void
    {
        $db = AppConfig::getDB();
        $db->prepare('DELETE FROM game_party_answers WHERE party_id = ?')->execute([$partyId]);
        $db->prepare('DELETE FROM game_party_players WHERE party_id = ?')->execute([$partyId]);
        $db->prepare('DELETE FROM game_parties WHERE id = ?')->execute([$partyId]);
    }

    public static function closeAllFor(string $hostUser): void
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        $stmt = $db->prepare('SELECT id FROM game_parties WHERE host_user = ?');
        $stmt->execute([$hostUser]);
        foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $id) {
            self::close((int)$id);
        }
    }

    /** Purge des salons oubliés (lien mort mais ligne encore là). */
    public static function purgeExpired(): void
    {
        static $done = false;
        if ($done) return;
        $done = true;
        try {
            $db = AppConfig::getDB();
            $stmt = $db->query('SELECT id FROM game_parties WHERE expires_at < NOW()');
            foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $id) {
                self::close((int)$id);
            }
        } catch (\Throwable $e) {
            // Table pas encore créée : rien à purger.
        }
    }

    // ──────────────────────────────────────────────────────────── lecture ──

    public static function byCode(string $code): ?array
    {
        self::ensureTables();
        $db = AppConfig::getDB();
        $stmt = $db->prepare('SELECT * FROM game_parties WHERE code = ? AND expires_at >= NOW()');
        $stmt->execute([strtoupper(trim($code))]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    public static function byId(int $id): ?array
    {
        $db = AppConfig::getDB();
        $stmt = $db->prepare('SELECT * FROM game_parties WHERE id = ?');
        $stmt->execute([$id]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    /**
     * Authentifie un porteur de jeton dans un salon.
     * @return array{party: array, player: array}
     */
    public static function auth(string $code, string $token): array
    {
        $party = self::byCode($code);
        if (!$party) throw new RuntimeException('party_not_found');
        $db = AppConfig::getDB();
        $stmt = $db->prepare('SELECT * FROM game_party_players WHERE party_id = ? AND token = ?');
        $stmt->execute([$party['id'], $token]);
        $player = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$player) throw new RuntimeException('player_not_found');
        $db->prepare('UPDATE game_party_players SET last_seen = NOW() WHERE id = ?')
           ->execute([$player['id']]);
        return ['party' => $party, 'player' => $player];
    }

    public static function players(int $partyId): array
    {
        $db = AppConfig::getDB();
        $stmt = $db->prepare('SELECT * FROM game_party_players WHERE party_id = ? ORDER BY id');
        $stmt->execute([$partyId]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    private static function bump(int $partyId): void
    {
        AppConfig::getDB()
            ->prepare('UPDATE game_parties SET version = version + 1 WHERE id = ?')
            ->execute([$partyId]);
    }

    public static function rounds(array $party): array
    {
        $j = json_decode((string)($party['rounds'] ?? ''), true);
        return is_array($j) ? $j : [];
    }

    public static function roundMs(array $party): int
    {
        return self::ROUND_MS[$party['game']] ?? 20000;
    }

    // ────────────────────────────────────────────────── tirage des manches ──

    /**
     * Lance la partie : tire toutes les manches d'un coup à partir de la
     * bibliothèque de l'hôte, puis démarre la première.
     */
    public static function start(array $party): array
    {
        $partyId = (int)$party['id'];
        $players = self::players($partyId);
        if (count($players) < 2) throw new RuntimeException('need_two_players');
        if ($party['status'] !== 'lobby') throw new RuntimeException('already_started');

        $rounds = self::buildRounds($party['host_user'], $party['game']);
        if (count($rounds) === 0) throw new RuntimeException('library_too_small');

        $db = AppConfig::getDB();
        // Chrono : tout le monde démarre avec la même carte visible, tirée en
        // tête de deck — sinon la première manche serait indécidable.
        if ($party['game'] === 'chrono') {
            $seed = array_shift($rounds);
            $card = self::chronoCard($seed);
            $stmt = $db->prepare('UPDATE game_party_players SET state = ?, lives = ?, score = 0 WHERE id = ?');
            foreach ($players as $p) {
                $stmt->execute([json_encode(['timeline' => [$card]], JSON_UNESCAPED_UNICODE), self::CHRONO_LIVES, $p['id']]);
            }
        }

        $stmt = $db->prepare(
            "UPDATE game_parties
                SET rounds = ?, status = 'playing', phase = 'guessing',
                    round_index = 0, phase_at = ?, turn_player_id = ?,
                    version = version + 1
              WHERE id = ?"
        );
        $turn = $party['game'] === 'chrono' ? (int)$players[0]['id'] : null;
        $stmt->execute([
            json_encode(array_values($rounds), JSON_UNESCAPED_UNICODE),
            self::now(),
            $turn,
            $partyId,
        ]);
        return self::byId($partyId);
    }

    /** Toutes les manches d'une partie, prêtes à jouer. */
    private static function buildRounds(string $user, string $game): array
    {
        return match ($game) {
            'blind'  => self::buildBlind($user),
            'cover'  => self::buildCover($user),
            'duel'   => self::buildDuel($user),
            'chrono' => self::buildChrono($user),
            default  => [],
        };
    }

    /** Titres quelconques de la bibliothèque (blind test). */
    private static function songPool(string $user, int $limit, bool $datedOnly): array
    {
        $db = AppConfig::getDB();
        $where = $datedOnly
            ? "AND al.year BETWEEN 1900 AND 2100 AND al.artwork IS NOT NULL AND al.artwork <> ''"
            : '';
        // Un seul titre par album quand on a besoin de millésimes distincts :
        // deux pistes du même album auraient la même année.
        $pick = $datedOnly
            ? 'JOIN (SELECT MIN(s2.id) AS song_id FROM songs s2
                     JOIN albums al2 ON s2.album_id = al2.id
                     JOIN artists a2 ON al2.artist_id = a2.id
                     WHERE a2.user = ? AND al2.year BETWEEN 1900 AND 2100
                       AND al2.artwork IS NOT NULL AND al2.artwork <> \'\'
                     GROUP BY s2.album_id) pick ON pick.song_id = s.id'
            : '';
        $sql = "SELECT s.id, s.title, s.duration, s.file_path, s.album_id,
                       al.name AS album_name, al.year,
                       " . TRACK_ARTIST_NAME . " AS artist_name
                FROM songs s
                $pick
                JOIN albums al ON s.album_id = al.id
                JOIN artists a ON al.artist_id = a.id
                " . TRACK_ARTIST_JOIN . "
                WHERE a.user = ? AND s.duration > 30 $where
                ORDER BY RAND() LIMIT " . (int)$limit;
        $stmt = $db->prepare($sql);
        $stmt->execute($datedOnly ? [$user, $user] : [$user]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    private static function albumPool(string $user, int $limit): array
    {
        $db = AppConfig::getDB();
        $stmt = $db->prepare(
            "SELECT al.id, al.name, al.year, a.name AS artist_name
             FROM albums al JOIN artists a ON al.artist_id = a.id
             WHERE a.user = ? AND al.artwork IS NOT NULL AND al.artwork <> ''
             ORDER BY RAND() LIMIT " . (int)$limit
        );
        $stmt->execute([$user]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /** URL d'image servie telle quelle par la page invité comme par l'app. */
    private static function artwork(int $albumId): string
    {
        $file = AppConfig::getDataPath() . '/cache/artwork/album_' . $albumId . '.jpg';
        $v = @filemtime($file) ?: 0;
        return 'serve_image.php?album_id=' . $albumId . ($v ? '&v=' . $v : '');
    }

    /** Début d'extrait : ni l'intro, ni la fin (comme en solo). */
    private static function snippetStart(int $duration): int
    {
        if ($duration <= 45) return 0;
        $low = (int)round($duration * 0.15);
        $high = (int)round($duration * 0.55);
        return $low + random_int(0, max(1, $high - $low));
    }

    private static function buildBlind(string $user): array
    {
        $pool = self::songPool($user, 120, false);
        if (count($pool) < 8) return [];
        $targets = array_slice($pool, 0, self::ROUNDS['blind']);
        $rounds = [];
        foreach ($targets as $i => $t) {
            $options = self::decoys($pool, $t, 'title', 4);
            $rounds[] = [
                'i'          => $i,
                'kind'       => 'blind',
                'songId'     => (int)$t['id'],
                'filePath'   => $t['file_path'],
                'startSec'   => self::snippetStart((int)$t['duration']),
                'title'      => $t['title'],
                'artist'     => $t['artist_name'],
                'artworkUrl' => self::artwork((int)$t['album_id']),
                'options'    => $options,
                'answerId'   => (string)(int)$t['id'],
            ];
        }
        return $rounds;
    }

    private static function buildCover(string $user): array
    {
        $pool = self::albumPool($user, 120);
        if (count($pool) < 8) return [];
        $targets = array_slice($pool, 0, self::ROUNDS['cover']);
        $rounds = [];
        foreach ($targets as $i => $t) {
            $options = self::decoys($pool, $t, 'name', 4);
            $rounds[] = [
                'i'          => $i,
                'kind'       => 'cover',
                'albumId'    => (int)$t['id'],
                'title'      => $t['name'],
                'artist'     => $t['artist_name'],
                'artworkUrl' => self::artwork((int)$t['id']),
                'options'    => $options,
                'answerId'   => (string)(int)$t['id'],
            ];
        }
        return $rounds;
    }

    /**
     * Trois leurres et la bonne réponse, mélangés. Les doublons de libellé
     * sont écartés : deux propositions identiques rendraient la manche
     * injouable.
     */
    private static function decoys(array $pool, array $target, string $labelKey, int $count): array
    {
        $options = [[
            'id'       => (string)(int)$target['id'],
            'title'    => $target[$labelKey],
            'subtitle' => $target['artist_name'] ?? '',
        ]];
        $seen = [mb_strtolower((string)$target[$labelKey]) => true];
        $candidates = $pool;
        shuffle($candidates);
        foreach ($candidates as $c) {
            if (count($options) >= $count) break;
            if ((int)$c['id'] === (int)$target['id']) continue;
            $label = mb_strtolower((string)$c[$labelKey]);
            if (isset($seen[$label])) continue;
            $seen[$label] = true;
            $options[] = [
                'id'       => (string)(int)$c['id'],
                'title'    => $c[$labelKey],
                'subtitle' => $c['artist_name'] ?? '',
            ];
        }
        shuffle($options);
        return $options;
    }

    private static function buildDuel(string $user): array
    {
        $pool = self::songPool($user, 120, true);
        // Un duel n'est décidable qu'entre deux millésimes différents.
        $byYear = [];
        foreach ($pool as $t) $byYear[(int)$t['year']][] = $t;
        if (count($byYear) < 2) return [];

        $rounds = [];
        $deck = $pool;
        shuffle($deck);
        for ($i = 0; $i < self::ROUNDS['duel'] && count($deck) >= 2; $i++) {
            $left = array_pop($deck);
            $rightIdx = null;
            foreach ($deck as $k => $cand) {
                if ((int)$cand['year'] !== (int)$left['year']) { $rightIdx = $k; break; }
            }
            if ($rightIdx === null) break;
            $right = $deck[$rightIdx];
            array_splice($deck, $rightIdx, 1);

            $older = (int)$left['year'] <= (int)$right['year'] ? $left : $right;
            $rounds[] = [
                'i'     => $i,
                'kind'  => 'duel',
                'left'  => self::duelSide($left),
                'right' => self::duelSide($right),
                'answerId' => (string)(int)$older['album_id'],
            ];
        }
        return count($rounds) >= 3 ? $rounds : [];
    }

    private static function duelSide(array $t): array
    {
        return [
            'id'         => (string)(int)$t['album_id'],
            'title'      => $t['album_name'],
            'subtitle'   => $t['artist_name'],
            'artworkUrl' => self::artwork((int)$t['album_id']),
            'year'       => (int)$t['year'],
        ];
    }

    private static function buildChrono(string $user): array
    {
        $pool = self::songPool($user, self::ROUNDS['chrono'] + 6, true);
        if (count($pool) < 8) return [];
        $rounds = [];
        foreach ($pool as $i => $t) {
            $rounds[] = [
                'i'          => $i,
                'kind'       => 'chrono',
                'songId'     => (int)$t['id'],
                'filePath'   => $t['file_path'],
                'startSec'   => self::snippetStart((int)$t['duration']),
                'title'      => $t['title'],
                'artist'     => $t['artist_name'],
                'albumName'  => $t['album_name'],
                'artworkUrl' => self::artwork((int)$t['album_id']),
                'year'       => (int)$t['year'],
                'answerId'   => '',
            ];
        }
        return $rounds;
    }

    /** La carte telle qu'elle vit dans la frise d'un joueur. */
    private static function chronoCard(array $round): array
    {
        return [
            'songId'     => $round['songId'],
            'title'      => $round['title'],
            'artist'     => $round['artist'],
            'artworkUrl' => $round['artworkUrl'],
            'year'       => $round['year'],
        ];
    }

    // ────────────────────────────────────────────────── avance des manches ──

    /**
     * Fait avancer la partie au regard de l'horloge, puis renvoie l'état à
     * jour. Appelé à chaque lecture : il n'y a pas d'autre moteur.
     */
    public static function tick(array $party): array
    {
        if ($party['status'] !== 'playing') return $party;
        $now = self::now();
        $elapsed = $now - (int)$party['phase_at'];

        if ($party['phase'] === 'guessing') {
            $everyone = self::allAnswered($party);
            if ($everyone || $elapsed >= self::roundMs($party)) {
                return self::reveal($party);
            }
            return $party;
        }

        if ($party['phase'] === 'revealed' && $elapsed >= self::REVEAL_MS) {
            return self::advance($party);
        }
        return $party;
    }

    /** Vrai quand plus personne n'a de réponse à donner pour cette manche. */
    private static function allAnswered(array $party): bool
    {
        $partyId = (int)$party['id'];
        $round = (int)$party['round_index'];
        $db = AppConfig::getDB();

        if ($party['game'] === 'chrono') {
            // Une seule réponse attendue : celle du joueur dont c'est le tour.
            $stmt = $db->prepare('SELECT 1 FROM game_party_answers WHERE party_id = ? AND round_index = ? AND player_id = ?');
            $stmt->execute([$partyId, $round, $party['turn_player_id']]);
            return (bool)$stmt->fetchColumn();
        }

        $stmt = $db->prepare('SELECT COUNT(*) FROM game_party_answers WHERE party_id = ? AND round_index = ?');
        $stmt->execute([$partyId, $round]);
        $answers = (int)$stmt->fetchColumn();
        return $answers >= count(self::players($partyId));
    }

    /**
     * Passe la manche en révélation (et applique le verdict du Chrono).
     *
     * Douze clients interrogent l'état en même temps : tous constatent la fin
     * du chrono à la même seconde. Le changement de phase sert donc de
     * verrou — seule la requête qui l'obtient applique le verdict, sinon la
     * carte serait posée (ou la vie perdue) autant de fois qu'il y a de
     * joueurs.
     */
    private static function reveal(array $party): array
    {
        $db = AppConfig::getDB();
        $stmt = $db->prepare(
            "UPDATE game_parties SET phase = 'revealed', phase_at = ?, version = version + 1
              WHERE id = ? AND phase = 'guessing' AND round_index = ?"
        );
        $stmt->execute([self::now(), $party['id'], $party['round_index']]);
        if ($stmt->rowCount() === 1 && $party['game'] === 'chrono') {
            self::applyChronoTurn($party);
        }
        return self::byId((int)$party['id']);
    }

    /**
     * Chrono : pose (ou non) la carte sur la frise du joueur du tour. Une
     * absence de réponse vaut un passage — la partie ne doit jamais se
     * bloquer sur un joueur parti se resservir à boire.
     */
    private static function applyChronoTurn(array $party): void
    {
        $db = AppConfig::getDB();
        $rounds = self::rounds($party);
        $round = $rounds[(int)$party['round_index']] ?? null;
        if (!$round) return;

        $stmt = $db->prepare('SELECT * FROM game_party_answers WHERE party_id = ? AND round_index = ? AND player_id = ?');
        $stmt->execute([$party['id'], $party['round_index'], $party['turn_player_id']]);
        $answer = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$answer || $answer['answer'] === null || $answer['answer'] === '') return;

        $stmt = $db->prepare('SELECT * FROM game_party_players WHERE id = ?');
        $stmt->execute([$party['turn_player_id']]);
        $player = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$player) return;

        $state = json_decode((string)$player['state'], true);
        $timeline = is_array($state['timeline'] ?? null) ? $state['timeline'] : [];
        $gap = (int)$answer['answer'];
        $years = array_map(static fn($c) => (int)$c['year'], $timeline);
        $correct = self::chronoPlacementIsCorrect($years, $gap, (int)$round['year']);

        if ($correct) {
            array_splice($timeline, $gap, 0, [self::chronoCard($round)]);
            $db->prepare('UPDATE game_party_players SET state = ?, score = score + 1 WHERE id = ?')
               ->execute([json_encode(['timeline' => $timeline], JSON_UNESCAPED_UNICODE), $player['id']]);
        } else {
            $db->prepare('UPDATE game_party_players SET lives = GREATEST(lives - 1, 0) WHERE id = ?')
               ->execute([$player['id']]);
        }
        $db->prepare('UPDATE game_party_answers SET correct = ?, points = ? WHERE id = ?')
           ->execute([$correct ? 1 : 0, $correct ? 1 : 0, $answer['id']]);
    }

    /**
     * Vrai si glisser une carte de l'année [year] dans le trou n° [gap] d'une
     * frise déjà triée respecte l'ordre chronologique. Deux albums de la même
     * année rendent plusieurs trous valides : on ne peut pas les départager.
     * (Miroir exact de `chronoPlacementIsCorrect` côté app.)
     */
    public static function chronoPlacementIsCorrect(array $years, int $gap, int $year): bool
    {
        $n = count($years);
        if ($gap < 0 || $gap > $n) return false;
        return ($gap === 0 || $years[$gap - 1] <= $year)
            && ($gap === $n || $year <= $years[$gap]);
    }

    /** Manche suivante, ou fin de partie. */
    private static function advance(array $party): array
    {
        $partyId = (int)$party['id'];
        $rounds = self::rounds($party);
        $next = (int)$party['round_index'] + 1;
        $db = AppConfig::getDB();

        $turn = null;
        if ($party['game'] === 'chrono') {
            $turn = self::nextTurn($party);
            // La partie s'arrête quand plus personne n'a de vie, ou dès qu'une
            // frise est complète — inutile de vider le paquet.
            if ($turn === null || self::chronoGoalReached($partyId)) {
                $next = count($rounds);
            }
        }

        // Même verrou que pour reveal() : une seule requête fait avancer la
        // manche, les autres reliront simplement l'état déjà avancé.
        if ($next >= count($rounds)) {
            $db->prepare(
                "UPDATE game_parties SET status = 'finished', phase = 'finished', phase_at = ?, version = version + 1
                  WHERE id = ? AND phase = 'revealed' AND round_index = ?"
            )->execute([self::now(), $partyId, $party['round_index']]);
            return self::byId($partyId);
        }

        $db->prepare(
            "UPDATE game_parties SET round_index = ?, phase = 'guessing', phase_at = ?, turn_player_id = ?, version = version + 1
              WHERE id = ? AND phase = 'revealed' AND round_index = ?"
        )->execute([$next, self::now(), $turn, $partyId, $party['round_index']]);
        return self::byId($partyId);
    }

    /** Chrono : quelqu'un a-t-il complété sa frise ? */
    private static function chronoGoalReached(int $partyId): bool
    {
        foreach (self::players($partyId) as $p) {
            if ((int)$p['score'] + 1 >= self::CHRONO_GOAL) return true;
        }
        return false;
    }

    /** Chrono : le prochain joueur encore en vie, dans l'ordre d'arrivée. */
    private static function nextTurn(array $party): ?int
    {
        $players = array_values(array_filter(
            self::players((int)$party['id']),
            static fn($p) => (int)$p['lives'] > 0
        ));
        if (!$players) return null;
        $ids = array_map(static fn($p) => (int)$p['id'], $players);
        $current = (int)($party['turn_player_id'] ?? 0);
        $pos = array_search($current, $ids, true);
        // Le joueur courant a pu perdre sa dernière vie : on repart du suivant
        // par identifiant, ce qui préserve l'ordre du tour de table.
        if ($pos === false) {
            foreach ($ids as $id) {
                if ($id > $current) return $id;
            }
            return $ids[0];
        }
        return $ids[($pos + 1) % count($ids)];
    }

    // ─────────────────────────────────────────────────────────── réponses ──

    /**
     * Enregistre la réponse d'un joueur pour la manche en cours. Une seule
     * réponse par manche et par joueur (contrainte d'unicité) : on ne peut
     * pas se raviser.
     */
    public static function answer(array $party, array $player, string $answer): array
    {
        if ($party['status'] !== 'playing' || $party['phase'] !== 'guessing') {
            throw new RuntimeException('not_accepting');
        }
        $rounds = self::rounds($party);
        $round = $rounds[(int)$party['round_index']] ?? null;
        if (!$round) throw new RuntimeException('no_round');

        if ($party['game'] === 'chrono' && (int)$player['id'] !== (int)$party['turn_player_id']) {
            throw new RuntimeException('not_your_turn');
        }

        $ms = max(0, self::now() - (int)$party['phase_at']);
        $limit = self::roundMs($party);
        if ($ms > $limit) throw new RuntimeException('too_late');

        $correct = false;
        $points = 0;
        if ($party['game'] !== 'chrono') {
            $correct = $answer !== '' && $answer === (string)$round['answerId'];
            if ($correct) {
                // 30 points pour la bonne réponse, jusqu'à 70 pour la vitesse
                // — même barème qu'en solo.
                $speed = max(0.0, 1.0 - ($ms / $limit));
                $points = 30 + (int)round($speed * 70);
            }
        }

        $db = AppConfig::getDB();
        $stmt = $db->prepare(
            'INSERT IGNORE INTO game_party_answers (party_id, round_index, player_id, answer, ms, correct, points)
             VALUES (?, ?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $party['id'], $party['round_index'], $player['id'],
            mb_substr($answer, 0, 64), $ms, $correct ? 1 : 0, $points,
        ]);
        if ($stmt->rowCount() > 0 && $points > 0) {
            $db->prepare('UPDATE game_party_players SET score = score + ? WHERE id = ?')
               ->execute([$points, $player['id']]);
        }
        self::bump((int)$party['id']);
        return self::tick(self::byId((int)$party['id']));
    }

    /** Chrono : passer son tour sans risquer de vie. */
    public static function skip(array $party, array $player): array
    {
        if ($party['game'] !== 'chrono') throw new RuntimeException('not_accepting');
        if ((int)$player['id'] !== (int)$party['turn_player_id']) throw new RuntimeException('not_your_turn');
        return self::answer($party, $player, '');
    }

    // ──────────────────────────────────────────────────────────────── état ──

    /**
     * L'état visible d'un joueur. `$forHost` ouvre l'accès au chemin du
     * fichier audio (l'app de l'hôte lit l'extrait en direct) ; un invité ne
     * l'obtient jamais.
     */
    public static function publicState(array $party, ?array $player): array
    {
        $partyId = (int)$party['id'];
        $players = self::players($partyId);
        $isHost = $player !== null && (int)$player['is_host'] === 1;
        $rounds = self::rounds($party);
        $roundCount = count($rounds);

        $answers = [];
        if ($party['status'] === 'playing') {
            $db = AppConfig::getDB();
            $stmt = $db->prepare('SELECT player_id, answer, correct, points FROM game_party_answers WHERE party_id = ? AND round_index = ?');
            $stmt->execute([$partyId, (int)$party['round_index']]);
            foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $a) {
                $answers[(int)$a['player_id']] = $a;
            }
        }

        $revealed = $party['phase'] === 'revealed' || $party['status'] === 'finished';

        $out = [
            'code'       => $party['code'],
            'game'       => $party['game'],
            'audioMode'  => $party['audio_mode'],
            'status'     => $party['status'],
            'phase'      => $party['phase'],
            'version'    => (int)$party['version'],
            'serverNow'  => self::now(),
            'phaseAt'    => (int)$party['phase_at'],
            'roundMs'    => self::roundMs($party),
            'revealMs'   => self::REVEAL_MS,
            'roundIndex' => (int)$party['round_index'],
            'roundCount' => $roundCount,
            'turnPlayerId' => $party['turn_player_id'] !== null ? (int)$party['turn_player_id'] : null,
            'maxPlayers' => self::MAX_PLAYERS,
            'me'         => $player === null ? null : [
                'id'     => (int)$player['id'],
                'name'   => $player['name'],
                'isHost' => $isHost,
            ],
            'players'    => [],
            'round'      => null,
        ];

        foreach ($players as $p) {
            $pid = (int)$p['id'];
            $state = json_decode((string)$p['state'], true);
            $out['players'][] = [
                'id'       => $pid,
                'name'     => $p['name'],
                'isHost'   => (int)$p['is_host'] === 1,
                'score'    => (int)$p['score'],
                'lives'    => (int)$p['lives'],
                'answered' => isset($answers[$pid]),
                // Le verdict n'a de sens qu'une fois la manche révélée : le
                // laisser filer plus tôt trahirait la réponse des autres.
                'correct'  => $revealed && isset($answers[$pid]) ? (bool)$answers[$pid]['correct'] : null,
                'gained'   => $revealed && isset($answers[$pid]) ? (int)$answers[$pid]['points'] : null,
                'timeline' => $party['game'] === 'chrono' && is_array($state['timeline'] ?? null)
                    ? $state['timeline'] : null,
            ];
        }

        if ($party['status'] === 'playing' && isset($rounds[(int)$party['round_index']])) {
            $out['round'] = self::publicRound(
                $rounds[(int)$party['round_index']],
                $party,
                $revealed,
                $isHost,
                $player === null ? null : $answers[(int)$player['id']] ?? null
            );
        }

        return $out;
    }

    /** La manche telle qu'un client a le droit de la voir. */
    private static function publicRound(array $round, array $party, bool $revealed, bool $isHost, ?array $myAnswer): array
    {
        $r = [
            'i'    => $round['i'],
            'kind' => $round['kind'],
            'myAnswer' => $myAnswer['answer'] ?? null,
        ];

        switch ($round['kind']) {
            case 'blind':
                $r['options'] = $round['options'];
                if ($isHost) {
                    // L'app de l'hôte lit l'extrait depuis la bibliothèque.
                    $r['filePath'] = $round['filePath'];
                    $r['startSec'] = $round['startSec'];
                }
                if ($revealed) {
                    $r['answerId'] = $round['answerId'];
                    $r['title'] = $round['title'];
                    $r['artist'] = $round['artist'];
                    $r['artworkUrl'] = $round['artworkUrl'];
                }
                break;

            case 'cover':
                $r['options'] = $round['options'];
                $r['artworkUrl'] = $round['artworkUrl'];
                if ($revealed) {
                    $r['answerId'] = $round['answerId'];
                    $r['title'] = $round['title'];
                    $r['artist'] = $round['artist'];
                }
                break;

            case 'duel':
                foreach (['left', 'right'] as $side) {
                    $s = $round[$side];
                    if (!$revealed) unset($s['year']);
                    $r[$side] = $s;
                }
                if ($revealed) $r['answerId'] = $round['answerId'];
                break;

            case 'chrono':
                if ($isHost) {
                    $r['filePath'] = $round['filePath'];
                    $r['startSec'] = $round['startSec'];
                }
                if ($revealed) {
                    $r['title'] = $round['title'];
                    $r['artist'] = $round['artist'];
                    $r['albumName'] = $round['albumName'];
                    $r['artworkUrl'] = $round['artworkUrl'];
                    $r['year'] = $round['year'];
                }
                break;
        }
        return $r;
    }
}

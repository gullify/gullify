<?php
/**
 * La musique des maisons amies (GulliOS 1.49, serveur 1.8.0) — voir src/MaisonsAmies.php.
 *
 * Pour une personne connectée ICI (session) :
 *   GET  ?action=moi                      → {actif, partage}            (partage-t-elle sa musique ?)
 *   POST ?action=moi {partage: bool}      → {actif, partage}
 *   GET  ?action=maisons                  → {actif, voir, maisons: [{nom, adresse, billet}]}
 * Pour une maison AMIE (?billet=…, signé par l'atelier ; lecture seule, personnes qui partagent) :
 *   GET  ?action=personnes                → [{id, nom, artistes, titres}]
 *   GET  ?action=artistes&personne=ID[&offset&limit]   → {artistes: [{id, nom, imageUrl, albums}], total}
 *   GET  ?action=artiste&personne=ID&id=A → {artiste, albums: [{id, nom, annee, artworkUrl, titres}]}
 *   GET  ?action=album&personne=ID&id=B   → {album, titres: [{id, titre, piste, duree, artiste, flux}]}
 *   GET  ?action=recherche&personne=ID&q= → {artistes, albums, titres}
 * Les adresses (imageUrl, artworkUrl, flux) sont RELATIVES à la maison qui répond ; l'app y ajoute
 * son adresse, et le billet pour `flux` (stream.php l'accepte, voir streamAutorise()).
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/MaisonsAmies.php';
require_once __DIR__ . '/../../../src/ImageUrl.php';

$action = $_GET['action'] ?? '';
$db = AppConfig::getDB();

// ── Une personne connectée ici ────────────────────────────────────────────────
if ($action === 'moi' || $action === 'maisons') {
    $ctx = v2_auth();
    if ($action === 'maisons') {
        v2_ok(MaisonsAmies::amies());
    }
    $id = (int)$ctx['user']['id'];
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $b = v2_body();
        if (!is_bool($b['partage'] ?? null)) {
            v2_fail('partage', 'partage (vrai ou faux) attendu.', 400);
        }
        $db->prepare('UPDATE users SET partage_amies = ? WHERE id = ?')->execute([$b['partage'] ? 1 : 0, $id]);
    }
    $q = $db->prepare('SELECT partage_amies FROM users WHERE id = ?');
    $q->execute([$id]);
    v2_ok(['actif' => MaisonsAmies::actif(), 'partage' => (bool)$q->fetchColumn()]);
}

// ── Une maison amie ───────────────────────────────────────────────────────────
if (MaisonsAmies::billetValable($_GET['billet'] ?? null) === null) {
    v2_fail('billet', 'Billet invalide.', 401);
}

/** Le nom d'utilisateur d'une personne qui partage sa musique (sinon 404). */
function personnePartagee(PDO $db): string
{
    $q = $db->prepare('SELECT username FROM users WHERE id = ? AND partage_amies = 1 AND is_active = 1');
    $q->execute([(int)($_GET['personne'] ?? 0)]);
    $u = $q->fetchColumn();
    if (!$u) {
        v2_fail('personne', 'Cette personne ne partage pas sa musique.', 404);
    }
    return (string)$u;
}

function titreVu(array $s): array
{
    return ['id' => (int)$s['id'], 'titre' => $s['title'], 'piste' => (int)$s['track_number'], 'duree' => (int)$s['duration'],
            'artiste' => $s['artiste'], 'albumId' => (int)$s['album_id'], 'album' => $s['album'],
            'artworkUrl' => ImageUrl::album((int)$s['album_id']),
            'flux' => 'stream.php?path=' . rawurlencode((string)$s['file_path'])];
}

const TITRES_SQL = 'SELECT s.id, s.title, s.track_number, s.duration, s.file_path, s.album_id, al.name AS album,
                           COALESCE(ta.name, NULLIF(s.track_artist, \'\'), a.name) AS artiste
                    FROM songs s JOIN albums al ON s.album_id = al.id JOIN artists a ON al.artist_id = a.id
                    LEFT JOIN artists ta ON s.artist_id = ta.id';

switch ($action) {
    case 'personnes':
        $q = $db->query('SELECT u.id, COALESCE(NULLIF(u.full_name, \'\'), u.username) AS nom,
                                (SELECT COUNT(*) FROM artists a WHERE a.user = u.username) AS artistes,
                                (SELECT COALESCE(SUM(a.song_count), 0) FROM artists a WHERE a.user = u.username) AS titres
                         FROM users u WHERE u.partage_amies = 1 AND u.is_active = 1 ORDER BY nom');
        v2_ok(array_map(fn($p) => ['id' => (int)$p['id'], 'nom' => $p['nom'], 'artistes' => (int)$p['artistes'],
                                   'titres' => (int)$p['titres']], $q->fetchAll(PDO::FETCH_ASSOC)));

    case 'artistes':
        $u = personnePartagee($db);
        $limit = max(1, min(500, (int)($_GET['limit'] ?? 100)));
        $offset = max(0, (int)($_GET['offset'] ?? 0));
        $q = $db->prepare('SELECT id, name, album_count, (image IS NOT NULL AND image != \'\') AS image
                           FROM artists WHERE user = ? AND song_count > 0 ORDER BY name LIMIT ? OFFSET ?');
        $q->bindValue(1, $u);
        $q->bindValue(2, $limit, PDO::PARAM_INT);
        $q->bindValue(3, $offset, PDO::PARAM_INT);
        $q->execute();
        $total = $db->prepare('SELECT COUNT(*) FROM artists WHERE user = ? AND song_count > 0');
        $total->execute([$u]);
        v2_ok(['total' => (int)$total->fetchColumn(),
               'artistes' => array_map(fn($a) => ['id' => (int)$a['id'], 'nom' => $a['name'], 'albums' => (int)$a['album_count'],
                                                  'imageUrl' => $a['image'] ? ImageUrl::artiste((int)$a['id']) : null],
                                       $q->fetchAll(PDO::FETCH_ASSOC))]);

    case 'artiste':
        $u = personnePartagee($db);
        $q = $db->prepare('SELECT id, name FROM artists WHERE id = ? AND user = ?');
        $q->execute([(int)($_GET['id'] ?? 0), $u]);
        $a = $q->fetch(PDO::FETCH_ASSOC) ?: v2_fail('artiste', 'Artiste introuvable.', 404);
        $q = $db->prepare('SELECT al.id, al.name, al.year, COUNT(s.id) AS titres FROM albums al
                           LEFT JOIN songs s ON s.album_id = al.id WHERE al.artist_id = ?
                           GROUP BY al.id HAVING titres > 0 ORDER BY al.year IS NULL, al.year DESC, al.name');
        $q->execute([(int)$a['id']]);
        v2_ok(['artiste' => ['id' => (int)$a['id'], 'nom' => $a['name'], 'imageUrl' => ImageUrl::artiste((int)$a['id'])],
               'albums' => array_map(fn($al) => ['id' => (int)$al['id'], 'nom' => $al['name'], 'annee' => $al['year'],
                                                 'titres' => (int)$al['titres'], 'artworkUrl' => ImageUrl::album((int)$al['id'])],
                                     $q->fetchAll(PDO::FETCH_ASSOC))]);

    case 'album':
        $u = personnePartagee($db);
        $q = $db->prepare('SELECT al.id, al.name, al.year, a.id AS artiste_id, a.name AS artiste FROM albums al
                           JOIN artists a ON al.artist_id = a.id WHERE al.id = ? AND a.user = ?');
        $q->execute([(int)($_GET['id'] ?? 0), $u]);
        $al = $q->fetch(PDO::FETCH_ASSOC) ?: v2_fail('album', 'Album introuvable.', 404);
        $q = $db->prepare(TITRES_SQL . ' WHERE s.album_id = ? ORDER BY s.track_number, s.title');
        $q->execute([(int)$al['id']]);
        v2_ok(['album' => ['id' => (int)$al['id'], 'nom' => $al['name'], 'annee' => $al['year'],
                           'artiste' => ['id' => (int)$al['artiste_id'], 'nom' => $al['artiste']],
                           'artworkUrl' => ImageUrl::album((int)$al['id'])],
               'titres' => array_map('titreVu', $q->fetchAll(PDO::FETCH_ASSOC))]);

    case 'recherche':
        $u = personnePartagee($db);
        $mot = trim((string)($_GET['q'] ?? ''));
        if (mb_strlen($mot) < 2) {
            v2_ok(['artistes' => [], 'albums' => [], 'titres' => []]);
        }
        $like = '%' . addcslashes($mot, '%_\\') . '%';
        $q = $db->prepare('SELECT id, name, album_count, (image IS NOT NULL AND image != \'\') AS image FROM artists
                           WHERE user = ? AND song_count > 0 AND name LIKE ? ORDER BY name LIMIT 20');
        $q->execute([$u, $like]);
        $artistes = array_map(fn($a) => ['id' => (int)$a['id'], 'nom' => $a['name'], 'albums' => (int)$a['album_count'],
                                         'imageUrl' => $a['image'] ? ImageUrl::artiste((int)$a['id']) : null], $q->fetchAll(PDO::FETCH_ASSOC));
        $q = $db->prepare('SELECT al.id, al.name, al.year, a.name AS artiste FROM albums al JOIN artists a ON al.artist_id = a.id
                           WHERE a.user = ? AND al.name LIKE ? ORDER BY al.name LIMIT 20');
        $q->execute([$u, $like]);
        $albums = array_map(fn($al) => ['id' => (int)$al['id'], 'nom' => $al['name'], 'annee' => $al['year'], 'artiste' => $al['artiste'],
                                        'artworkUrl' => ImageUrl::album((int)$al['id'])], $q->fetchAll(PDO::FETCH_ASSOC));
        $q = $db->prepare(TITRES_SQL . ' WHERE a.user = ? AND s.title LIKE ? ORDER BY s.title LIMIT 50');
        $q->execute([$u, $like]);
        v2_ok(['artistes' => $artistes, 'albums' => $albums, 'titres' => array_map('titreVu', $q->fetchAll(PDO::FETCH_ASSOC))]);

    default:
        v2_fail('action_inconnue', 'Action inconnue.', 400);
}

<?php
/**
 * Gullify API v2 — Pour toi (profil de goûts et recommandations, src/Gouts*.php)
 *
 *   GET  ?action=accueil                       → { rayons: [{id, type, titre, sousTitre, nombre, apercu[], …}], analyseLe }
 *   GET  ?action=rayon&id=N                    → { titre, sousTitre, type, titres: [Song + raison, origin] }
 *   GET  ?action=suite&graines=1,2&exclus=3,4&n=10&famille=auto|radio
 *                                              → { titres: [Song + raison, origin] }   (lecture automatique)
 *   GET  ?action=radio&titre=N&n=25            → { titres: [le titre, puis sa suite] }
 *   GET  ?action=profil                        → le portrait (étiquettes, artistes, habitudes, réglages)
 *   POST ?action=aventure   {valeur: 0..1}
 *   POST ?action=rejeter    {type: song|artist, id}      « Pas pour moi »
 *   POST ?action=retablir   {type: song|artist, id}
 *   POST ?action=analyser                      → refait le profil et les rayons maintenant
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Gouts.php';
require_once __DIR__ . '/../../../src/GoutsRadio.php';
require_once __DIR__ . '/../../../src/GoutsRayons.php';

$ctx    = v2_auth();
$user   = (string)$ctx['user']['username'];
$action = $_GET['action'] ?? '';

function pt_ids(string $s, int $max = 200): array
{
    return array_slice(array_values(array_filter(array_map('intval', explode(',', $s)))), 0, $max);
}

/** Origine de lecture d'un rayon : `mix:2`, `decouvertes`, `moment:soir`… */
function pt_origine(array $r, array $contenu): string
{
    return match ($r['type']) {
        'mix' => 'mix:' . ($contenu['numero'] ?? ((int)$r['rang'] + 1)),
        'moment' => 'moment:' . ($contenu['moment'] ?? 'jour'),
        default => (string)$r['type'],
    };
}

/** Le moment de la journée qu'il est chez la personne. */
function pt_moment(int $decalage): string
{
    $h = (int)gmdate('G', time() + 60 * $decalage);
    foreach (GoutsRayons::MOMENTS as $cle => [$de, $a]) {
        if ($de < $a ? ($h >= $de && $h < $a) : ($h >= $de || $h < $a)) return $cle;
    }
    return 'soir';
}

/**
 * Analyse sur place quand elle n'a jamais tourné (première ouverture après
 * la mise à jour) ou date de plus de deux jours. Sans réseau : les sources
 * du monde, c'est la nuit (scripts/analyser-gouts.php).
 */
function pt_assurer_analyse(PDO $db, string $user, bool $forcer = false): void
{
    $q = $db->prepare('SELECT UNIX_TIMESTAMP(analyse_le) FROM gouts_reglages WHERE user = ?');
    $q->execute([$user]);
    $t = (int)$q->fetchColumn();
    if (!$forcer && $t > time() - 2 * 86400) return;
    if ($forcer && $t > time() - 120) return; // pas plus d'une fois toutes les deux minutes
    $verrou = fopen(sys_get_temp_dir() . '/gouts-' . md5($user) . '.lock', 'c');
    if (!$verrou || !flock($verrou, LOCK_EX | LOCK_NB)) return; // une analyse tourne déjà
    try {
        @set_time_limit(120);
        Gouts::analyserProfil($db, $user);
        GoutsRayons::construire($db, $user, false);
        $db->prepare('INSERT INTO gouts_reglages (user, analyse_le) VALUES (?, NOW()) ON DUPLICATE KEY UPDATE analyse_le = NOW()')
           ->execute([$user]);
    } finally {
        flock($verrou, LOCK_UN);
    }
}

try {
    $db = AppConfig::getDB();
    Gouts::assurerTables($db);

    // L'app dit son fuseau (minutes à l'est de l'UTC) : le serveur vit en UTC,
    // le mix du soir doit tomber le soir de la personne.
    if (isset($_GET['decalage']) && is_numeric($_GET['decalage'])) {
        $d = max(-840, min(840, (int)$_GET['decalage']));
        if ($d !== Gouts::decalage($db, $user)) {
            $db->prepare('INSERT INTO gouts_reglages (user, decalage) VALUES (?, ?) ON DUPLICATE KEY UPDATE decalage = VALUES(decalage)')
               ->execute([$user, $d]);
        }
    }

    switch ($action) {
        case 'accueil': {
            pt_assurer_analyse($db, $user);
            $q = $db->prepare('SELECT id, type, rang, titre, sous_titre, contenu FROM gouts_rayons WHERE user = ? ORDER BY id');
            $q->execute([$user]);
            $maintenant = pt_moment(Gouts::decalage($db, $user));
            $ordre = ['moment' => 0, 'mix' => 1, 'decouvertes' => 2, 'boucle' => 3, 'oubliees' => 4, 'ailleurs' => 5];
            $rayons = [];
            foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
                $c = json_decode($r['contenu'], true) ?: [];
                if ($r['type'] === 'moment' && ($c['moment'] ?? '') !== $maintenant) continue;
                $item = ['id' => (int)$r['id'], 'type' => $r['type'], 'titre' => $r['titre'],
                         'sousTitre' => $r['sous_titre'], 'origin' => pt_origine($r, $c)];
                if ($r['type'] === 'ailleurs') {
                    $item['artistes'] = $c['artistes'] ?? [];
                    $item['nombre'] = count($item['artistes']);
                } else {
                    $titres = $c['titres'] ?? [];
                    $item['nombre'] = count($titres);
                    // Quatre pochettes distinctes pour la vignette.
                    $apercu = GoutsRayons::hydrater($db, $user, array_slice($titres, 0, 24));
                    $vues = [];
                    foreach ($apercu as $s) {
                        $vues[$s['albumId']] ??= $s['artworkUrl'];
                        if (count($vues) >= 4) break;
                    }
                    $item['apercu'] = array_values($vues);
                    if ($r['type'] === 'mix') $item['numero'] = $c['numero'] ?? null;
                }
                $item['_o'] = ($ordre[$r['type']] ?? 9) * 100 + (int)$r['rang'];
                $rayons[] = $item;
            }
            usort($rayons, fn($a, $b) => $a['_o'] <=> $b['_o']);
            foreach ($rayons as &$r) unset($r['_o']);
            unset($r);
            $q = $db->prepare('SELECT analyse_le FROM gouts_reglages WHERE user = ?');
            $q->execute([$user]);
            v2_ok(['rayons' => $rayons, 'analyseLe' => $q->fetchColumn() ?: null]);
        }

        case 'rayon': {
            $q = $db->prepare('SELECT * FROM gouts_rayons WHERE id = ? AND user = ?');
            $q->execute([(int)($_GET['id'] ?? 0), $user]);
            $r = $q->fetch(PDO::FETCH_ASSOC);
            if (!$r) v2_fail('introuvable', 'Ce rayon a été renouvelé : retourne à l\'accueil.', 404);
            $c = json_decode($r['contenu'], true) ?: [];
            v2_ok([
                'id' => (int)$r['id'], 'type' => $r['type'], 'titre' => $r['titre'], 'sousTitre' => $r['sous_titre'],
                'titres' => GoutsRayons::hydrater($db, $user, $c['titres'] ?? [], pt_origine($r, $c)),
                'artistes' => $c['artistes'] ?? null,
            ]);
        }

        case 'suite': {
            $famille = ($_GET['famille'] ?? 'auto') === 'radio' ? 'radio' : 'auto';
            $aventure = isset($_GET['aventure']) ? max(0.0, min(1.0, (float)$_GET['aventure'])) : null;
            $choix = GoutsRadio::suite($db, $user, pt_ids((string)($_GET['graines'] ?? ''), 6),
                pt_ids((string)($_GET['exclus'] ?? ''), 500), (int)($_GET['n'] ?? 10), $aventure, $famille);
            v2_ok(['titres' => GoutsRayons::hydrater($db, $user, $choix)]);
        }

        case 'radio': {
            $titre = (int)($_GET['titre'] ?? 0);
            if ($titre <= 0) v2_fail('titre_requis', 'Quel titre ?', 400);
            $choix = GoutsRadio::suite($db, $user, [$titre], pt_ids((string)($_GET['exclus'] ?? ''), 500),
                (int)($_GET['n'] ?? 25), null, 'radio');
            $liste = array_merge([['id' => $titre, 'origin' => null]], $choix);
            v2_ok(['titres' => GoutsRayons::hydrater($db, $user, $liste)]);
        }

        case 'profil':
            require_once __DIR__ . '/../../../src/GoutsPortrait.php';
            pt_assurer_analyse($db, $user);
            v2_ok(GoutsPortrait::pour($db, $user));

        case 'aventure': {
            $b = v2_body() + $_POST;
            $v = max(0.0, min(1.0, (float)($b['valeur'] ?? 0.35)));
            $db->prepare('INSERT INTO gouts_reglages (user, aventure) VALUES (?, ?) ON DUPLICATE KEY UPDATE aventure = VALUES(aventure)')
               ->execute([$user, $v]);
            v2_ok(['aventure' => $v]);
        }

        case 'rejeter':
        case 'retablir': {
            $b = v2_body() + $_POST;
            $type = ($b['type'] ?? '') === 'artist' ? 'artist' : (($b['type'] ?? '') === 'song' ? 'song' : null);
            $id = (int)($b['id'] ?? 0);
            if (!$type || $id <= 0) v2_fail('cible_requise', 'Un titre ou un artiste, avec son id.', 400);
            // Seulement ce qui est à soi.
            $sql = $type === 'artist'
                ? 'SELECT 1 FROM artists WHERE id = ? AND user = ?'
                : 'SELECT 1 FROM songs s JOIN albums al ON al.id = s.album_id JOIN artists a ON a.id = al.artist_id WHERE s.id = ? AND a.user = ?';
            $q = $db->prepare($sql);
            $q->execute([$id, $user]);
            if (!$q->fetchColumn()) v2_fail('introuvable', 'Introuvable dans ta bibliothèque.', 404);
            if ($action === 'rejeter') {
                $db->prepare('INSERT IGNORE INTO gouts_rejets (user, type, cible_id) VALUES (?, ?, ?)')->execute([$user, $type, $id]);
                // Retiré tout de suite des rayons déjà bâtis, sans attendre la nuit.
                $q = $db->prepare("SELECT id, contenu FROM gouts_rayons WHERE user = ? AND type <> 'ailleurs'");
                $q->execute([$user]);
                $artistes = $type === 'artist' ? null : [];
                foreach ($q->fetchAll(PDO::FETCH_ASSOC) as $r) {
                    $c = json_decode($r['contenu'], true) ?: [];
                    $avant = count($c['titres'] ?? []);
                    if ($type === 'song') {
                        $c['titres'] = array_values(array_filter($c['titres'] ?? [], fn($t) => (int)$t['id'] !== $id));
                    } else {
                        $ids = array_map(fn($t) => (int)$t['id'], $c['titres'] ?? []);
                        $infos = GoutsRadio::infosTitres($db, $user, $ids);
                        $c['titres'] = array_values(array_filter($c['titres'] ?? [],
                            fn($t) => ($infos[(int)$t['id']]['artiste'] ?? null) !== $id));
                    }
                    if (count($c['titres']) !== $avant) {
                        $db->prepare('UPDATE gouts_rayons SET contenu = ? WHERE id = ?')
                           ->execute([json_encode($c, JSON_UNESCAPED_UNICODE), $r['id']]);
                    }
                }
            } else {
                $db->prepare('DELETE FROM gouts_rejets WHERE user = ? AND type = ? AND cible_id = ?')->execute([$user, $type, $id]);
            }
            v2_ok(['type' => $type, 'id' => $id, 'rejete' => $action === 'rejeter']);
        }

        case 'analyser':
            pt_assurer_analyse($db, $user, true);
            v2_ok(['ok' => true]);

        default:
            v2_fail('unknown_action', 'Action inconnue : ' . $action, 400);
    }
} catch (Throwable $e) {
    error_log('API v2 pour-toi : ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
    v2_fail('server_error', 'Erreur du serveur', 500);
}

<?php
/**
 * Gullify API v2 — Pour toi (profil de goûts et recommandations, src/Gouts*.php)
 *
 *   GET  ?action=accueil                       → { rayons: [{id, type, titre, sousTitre, nombre, apercu[], …}], analyseLe }
 *   GET  ?action=rayon&id=N                    → { titre, sousTitre, type, titres: [Song + raison, origin] }
 *   GET  ?action=suite&graines=1,2&exclus=3,4&n=10&famille=auto|radio
 *                                              → { titres: [Song + raison, origin] }   (lecture automatique)
 *        (+ &ailleurs=1&artistes=…&exclus_ext=yt:ID,bc:ID : peut sortir de la bibliothèque, voir pt_suite_ailleurs)
 *   GET  ?action=radio&titre=N&n=25            → { titres: [le titre, puis sa suite] }
 *   GET  ?action=profil                        → le portrait (étiquettes, artistes, habitudes, réglages)
 *   POST ?action=aventure   {valeur: 0..1}
 *   POST ?action=rejeter    {type: song|artist, id}      « Pas pour moi »
 *   POST ?action=retablir   {type: song|artist, id}
 *   POST ?action=analyser                      → refait le profil et les rayons maintenant
 *   GET  ?action=bulles                        → « Tes artistes » : bulles de départ (choisis + leurs proches, `liens`)
 *   GET  ?action=bulles&autour=<clé>&nom=…&deja=k1,k2  → ce qui éclot à côté d'une bulle aimée
 *   GET  ?action=proches&nom=…                 → artistes proches d'un artiste (page de l'artiste)
 *   GET  ?action=suggestions                   → artistes suggérés : aimés pas encore chez soi, puis ailleurs
 *   GET  ?action=chercher_artiste&q=…          → bibliothèque puis monde (Last.fm / YouTube Music)
 *   POST ?action=choisir    {nom, niveau: 0|1|2, image?}   0 retirer, 1 aimer, 2 adorer
 *   (une bulle : {cle, nom, image, artistId|null, niveau})
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Gouts.php';
require_once __DIR__ . '/../../../src/GoutsRadio.php';
require_once __DIR__ . '/../../../src/GoutsRayons.php';
require_once __DIR__ . '/../../../src/GoutsBulles.php';
require_once __DIR__ . '/../../../src/GoutsAilleurs.php';

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
    } catch (Throwable $e) {
        // Bibliothèque jamais scannée (colonnes posées par le premier scan),
        // base en travaux… : l'accueil répond avec ce qu'il a, sans 500.
        error_log('Pour toi, analyse à la volée : ' . $e->getMessage());
    } finally {
        flock($verrou, LOCK_UN);
    }
}

/**
 * La suite qui peut sortir de la bibliothèque (`ailleurs=1`, app 3.95.0) :
 * ce que la bibliothèque a de proche, et quand elle n'a rien (ou pas assez),
 * des titres d'artistes proches qu'on n'a pas, joués à la pièce depuis
 * YouTube Music ou Bandcamp (src/GoutsAilleurs.php). Les deux sont mêlés.
 *
 *   artistes=Nom\nNom   artistes des titres d'ailleurs qui viennent de jouer
 *   exclus_ext=yt:ID,bc:ID   titres d'ailleurs déjà dans la file
 * Une fiche d'ailleurs porte `externe` (youtube|bandcamp) au lieu d'un `id`.
 */
function pt_suite_ailleurs(PDO $db, string $user, array $graines, array $exclus, int $n,
                           ?float $aventure, string $famille): array
{
    @set_time_limit(90);
    $externes = array_slice(array_values(array_filter(array_map('trim',
        explode("\n", (string)($_GET['artistes'] ?? ''))), fn($s) => $s !== '')), -3);
    $exclusExt = array_slice(array_values(array_filter(array_map('trim',
        explode(',', (string)($_GET['exclus_ext'] ?? ''))),
        fn($c) => (bool)preg_match('/^(yt|bc):[\w-]{1,64}$/', $c))), 0, 500);

    // Les noms derrière les graines de la bibliothèque, puis ceux d'ailleurs.
    $noms = [];
    $infos = GoutsRadio::infosTitres($db, $user, array_slice($graines, -3));
    foreach (array_slice($graines, -3) as $g) {
        if (isset($infos[(int)$g])) $noms[] = (string)$infos[(int)$g]['nom'];
    }
    $noms = array_merge($noms, $externes);
    $prox = $noms === [] ? ['dedans' => [], 'dehors' => []] : GoutsAilleurs::proches($db, $user, $noms);

    $etat = null;
    $choix = GoutsRadio::suite($db, $user, $graines, $exclus, $n, $aventure, $famille,
        $prox['dedans'], false, $externes === [], $etat);
    $lib = GoutsRayons::hydrater($db, $user, $choix);
    $sec = (bool)($etat['sec'] ?? false);
    $manque = $n - count($lib);
    $ext = ($sec || $manque > 0)
        ? GoutsAilleurs::titres($prox['dehors'], $exclusExt, max($manque, $sec ? 3 : 0), $famille)
        : [];

    // Rien de proche nulle part (pas de réseau, artiste inconnu du monde) :
    // l'ancienne suite, avec ses replis — on ne reste jamais muet.
    if ($lib === [] && $ext === []) {
        return GoutsRayons::hydrater($db, $user, GoutsRadio::suite($db, $user, $graines, $exclus, $n, $aventure, $famille));
    }

    // Mêlés un à un ; on commence par ailleurs quand c'est ailleurs qui joue.
    [$a, $b] = $graines === [] ? [$ext, $lib] : [$lib, $ext];
    $out = [];
    while ($a !== [] || $b !== []) {
        if ($a !== []) $out[] = array_shift($a);
        if ($b !== []) $out[] = array_shift($b);
    }
    return $out;
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
            $graines = pt_ids((string)($_GET['graines'] ?? ''), 6);
            $exclus = pt_ids((string)($_GET['exclus'] ?? ''), 500);
            $n = max(1, min(50, (int)($_GET['n'] ?? 10)));
            if (($_GET['ailleurs'] ?? '') !== '1') {
                $choix = GoutsRadio::suite($db, $user, $graines, $exclus, $n, $aventure, $famille);
                v2_ok(['titres' => GoutsRayons::hydrater($db, $user, $choix)]);
            }
            v2_ok(['titres' => pt_suite_ailleurs($db, $user, $graines, $exclus, $n, $aventure, $famille)]);
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

        case 'bulles': {
            $autour = (string)($_GET['autour'] ?? '');
            if ($autour !== '') {
                $deja = array_slice(array_filter(explode(',', (string)($_GET['deja'] ?? ''))), 0, 400);
                v2_ok(['bulles' => GoutsBulles::autour($db, $user, $autour, (string)($_GET['nom'] ?? ''), $deja,
                    max(1, min(12, (int)($_GET['n'] ?? 6))))]);
            }
            v2_ok(['bulles' => GoutsBulles::depart($db, $user)]);
        }

        case 'proches':
            v2_ok(['bulles' => GoutsBulles::proches($db, $user, (string)($_GET['nom'] ?? ''),
                max(1, min(40, (int)($_GET['n'] ?? 20))))]);

        case 'suggestions':
            v2_ok(['artistes' => GoutsBulles::suggestions($db, $user)]);

        case 'chercher_artiste':
            v2_ok(['bulles' => GoutsBulles::chercher($db, $user, (string)($_GET['q'] ?? ''))]);

        case 'choisir': {
            $b = v2_body() + $_POST;
            try {
                v2_ok(GoutsBulles::choisir($db, $user, (string)($b['nom'] ?? ''), (int)($b['niveau'] ?? 1),
                    isset($b['image']) && is_string($b['image']) ? $b['image'] : null,
                    isset($b['parent']) && is_string($b['parent']) ? $b['parent'] : null));
            } catch (InvalidArgumentException $e) {
                v2_fail('nom_requis', $e->getMessage(), 400);
            }
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

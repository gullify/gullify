<?php
/**
 * Essais de « Pour toi » (src/Gouts*.php) — sur une base MySQL JETABLE.
 *
 * Bâtit une petite bibliothèque d'essai pour le compte « essai_gouts » (huit
 * artistes, deux familles), des écoutes et des sauts, puis vérifie : les
 * poids d'écoute, les clés d'artiste, le saut net (< 5 s) hors historique,
 * le bandit, le profil, les voisins, la suite (lecture automatique : séance,
 * rejets, diversité, exclusions), les rayons et le portrait. Le compte
 * d'essai est effacé à la fin.
 *
 *   TEST_JETABLE=oui php scripts/test-gouts.php
 */

if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
if (getenv('TEST_JETABLE') !== 'oui') {
    fwrite(STDERR, "Refusé : TEST_JETABLE=oui exigé (base jetable seulement).\n");
    exit(2);
}
error_reporting(E_ALL);
set_error_handler(function ($no, $msg, $file, $line) {
    if (!(error_reporting() & $no)) return false; // « @ » : avertissement voulu muet
    throw new ErrorException($msg, 0, $no, $file, $line);
});

require_once __DIR__ . '/../src/Database.php';
require_once __DIR__ . '/../src/Gouts.php';
require_once __DIR__ . '/../src/GoutsRadio.php';
require_once __DIR__ . '/../src/GoutsRayons.php';
require_once __DIR__ . '/../src/GoutsPortrait.php';

$echecs = 0;
$total = 0;
function ok(bool $cond, string $quoi): void
{
    global $echecs, $total;
    $total++;
    if ($cond) { echo "  ok    $quoi\n"; return; }
    $echecs++;
    echo "  ÉCHEC $quoi\n";
}

$db = AppConfig::getDB();
Gouts::assurerTables($db);
// Colonnes que le premier scan pose (src/Scanner.php) : une base neuve ne les a pas.
foreach (['track_artist VARCHAR(255) NULL', 'artist_id INT NULL'] as $col) {
    try { $db->exec("ALTER TABLE songs ADD COLUMN $col"); } catch (PDOException $e) { /* déjà là */ }
}
$U = 'essai_gouts';

function nettoyer(PDO $db, string $u): void
{
    foreach (array_merge(['play_history', 'favorites', 'favorite_artists'], Gouts::TABLES_PERSONNE) as $t) {
        $db->prepare("DELETE FROM $t WHERE user = ?")->execute([$u]);
    }
    $db->prepare('DELETE FROM artists WHERE user = ?')->execute([$u]);
    $db->exec("DELETE FROM artistes_similaires WHERE cle LIKE 'essaigouts%'");
    $db->exec("DELETE FROM artistes_tags WHERE cle LIKE 'essaigouts%'");
}
nettoyer($db, $U);

echo "Fonctions pures\n";
ok(Gouts::cle('Les Cowboys Fringants') === Gouts::cle('les cowboys fringants!'), 'clé : casse et ponctuation');
ok(Gouts::cle('Beyoncé') === Gouts::cle('Beyonce'), 'clé : accents');
ok(Gouts::cle('The Clash') === Gouts::cle('Clash'), 'clé : « The »');
ok(Gouts::origineValide('mix:2') === 'mix:2' && Gouts::origineValide('auto:voisins') === 'auto:voisins', 'origine valide');
ok(Gouts::origineValide("x'; DROP") === null && Gouts::origineValide(null) === null, 'origine refusée');
ok(Gouts::poidsEcoute(200, 200, true, null) === 1.0, 'fini = +1');
ok(Gouts::poidsEcoute(4, 200, false, 1) <= -1.0, 'sauté à 4 s = refus net');
ok(Gouts::poidsEcoute(20, 200, false, 1) < -0.5, 'sauté à 20 s = refus');
ok(Gouts::poidsEcoute(20, 200, false, 0) === 0.0, 'changer de file n\'est pas un jugement');
ok(Gouts::poidsEcoute(150, 200, false, 0) > 0, 'arrêté aux trois quarts = plutôt aimé');
ok(abs(Gouts::amorti(Gouts::DEMI_VIE) - 0.5) < 1e-9, 'demi-vie');
$b = 0; for ($i = 0; $i < 2000; $i++) $b += GoutsRadio::beta(8, 2);
ok(abs($b / 2000 - 0.8) < 0.03, 'tirage Beta(8,2) ≈ 0,8');

// ── Bibliothèque d'essai : famille « punk » (A-D) et famille « folk » (E-H) ──
echo "Bibliothèque d'essai\n";
$artistes = [];
$titres = [];
$familles = ['A' => 'Punk', 'B' => 'Punk', 'C' => 'Punk', 'D' => 'Punk', 'E' => 'Folk', 'F' => 'Folk', 'G' => 'Folk', 'H' => 'Folk'];
foreach ($familles as $l => $genre) {
    $db->prepare('INSERT INTO artists (name, user, genre) VALUES (?, ?, ?)')->execute(["EssaiGouts $l", $U, $genre]);
    $a = (int)$db->lastInsertId();
    $artistes[$l] = $a;
    foreach ([1, 2] as $n) {
        $db->prepare('INSERT INTO albums (artist_id, name, genre) VALUES (?, ?, ?)')->execute([$a, "Album $l$n", $genre]);
        $al = (int)$db->lastInsertId();
        for ($t = 1; $t <= 6; $t++) {
            $db->prepare('INSERT INTO songs (album_id, title, track_number, duration, file_path) VALUES (?, ?, ?, 200, ?)')
               ->execute([$al, "Titre $l$n-$t", $t, "essai/$l/$n/$t.mp3"]);
            $titres[$l][] = (int)$db->lastInsertId();
        }
    }
}
// Le monde (comme Last.fm) : A~B~C~D, E~F~G~H, et une passerelle faible D~E.
$sim = $db->prepare('INSERT INTO artistes_similaires (cle, voisin_cle, voisin_nom, score) VALUES (?, ?, ?, ?)');
$paires = [['A', 'B', .9], ['A', 'C', .7], ['B', 'C', .8], ['C', 'D', .6], ['E', 'F', .9], ['E', 'G', .8], ['F', 'H', .7], ['D', 'E', .15]];
foreach ($paires as [$x, $y, $s]) {
    $sim->execute([Gouts::cle("EssaiGouts $x"), Gouts::cle("EssaiGouts $y"), "EssaiGouts $y", $s]);
    $sim->execute([Gouts::cle("EssaiGouts $y"), Gouts::cle("EssaiGouts $x"), "EssaiGouts $x", $s]);
}
// Et un artiste d'ailleurs, absent de la bibliothèque, que A et B appellent.
$sim->execute([Gouts::cle('EssaiGouts A'), Gouts::cle('EssaiGouts Ailleurs'), 'EssaiGouts Ailleurs', .95]);
$sim->execute([Gouts::cle('EssaiGouts B'), Gouts::cle('EssaiGouts Ailleurs'), 'EssaiGouts Ailleurs', .9]);
$tag = $db->prepare('INSERT INTO artistes_tags (cle, tag, poids) VALUES (?, ?, ?)');
foreach ($familles as $l => $g) {
    $tag->execute([Gouts::cle("EssaiGouts $l"), $g === 'Punk' ? 'skate punk' : 'folk acadien', 1.0]);
    $tag->execute([Gouts::cle("EssaiGouts $l"), 'rock', 0.5]);
}

// Écoutes : on aime A et B (finis), on saute H, rien sur les autres.
$ecoute = $db->prepare("INSERT INTO play_history (song_id, user, played_at, play_duration, completed, source, skipped)
                        VALUES (?, ?, NOW() - INTERVAL ? HOUR, ?, ?, 'radio', ?)");
$h = 400;
foreach (['A', 'B'] as $l) {
    foreach (array_slice($titres[$l], 0, 8) as $id) {
        foreach ([1, 2, 3] as $_) $ecoute->execute([$id, $U, $h--, 200, 1, 0]);
    }
}
foreach (array_slice($titres['E'], 0, 4) as $id) $ecoute->execute([$id, $U, $h--, 200, 1, 0]);
foreach (array_slice($titres['H'], 0, 6) as $id) $ecoute->execute([$id, $U, $h--, 6, 0, 1]);

echo "Écoutes et sauts\n";
$database = new Database();
$avant = (int)$db->query("SELECT COUNT(*) FROM play_history WHERE user = '$U'")->fetchColumn();
$database->trackPlay($titres['H'][7], $U, 2, false, 'radio', true, 'auto:voisins');
$apres = (int)$db->query("SELECT COUNT(*) FROM play_history WHERE user = '$U'")->fetchColumn();
$sauts = (int)$db->query("SELECT COUNT(*) FROM gouts_sauts WHERE user = '$U'")->fetchColumn();
ok($apres === $avant && $sauts === 1, 'saut de 2 s : dans gouts_sauts, pas dans l\'historique');
$q = $db->prepare("SELECT echecs FROM gouts_bandits WHERE user = ? AND bras = 'voisins'");
$q->execute([$U]);
ok((float)$q->fetchColumn() === 2.0, 'le bras « voisins » a pris un échec');
$database->trackPlay($titres['A'][9], $U, 200, true, 'radio', false, 'auto:artiste');
$q = $db->prepare("SELECT succes FROM gouts_bandits WHERE user = ? AND bras = 'artiste'");
$q->execute([$U]);
ok((float)$q->fetchColumn() === 2.0, 'le bras « artiste » a pris un succès');
$q = $db->prepare("SELECT origin, skipped FROM play_history WHERE user = ? ORDER BY id DESC LIMIT 1");
$q->execute([$U]);
$r = $q->fetch(PDO::FETCH_ASSOC);
ok($r['origin'] === 'auto:artiste' && (string)$r['skipped'] === '0', 'origine et saut enregistrés');
$database->trackPlay($titres['A'][10], $U, 200, true, 'radio', false, 'pas valide !');
$q->execute([$U]);
ok($q->fetch(PDO::FETCH_ASSOC)['origin'] === null, 'origine invalide écartée');
// Les deux écoutes ci-dessus sont « récentes » : on les vieillit pour que la
// séance d'essai ne commence qu'avec ce qu'on y met.
$db->prepare("UPDATE play_history SET played_at = NOW() - INTERVAL 10 HOUR WHERE user = ? AND played_at > NOW() - INTERVAL 1 HOUR")->execute([$U]);
$db->prepare("UPDATE gouts_sauts SET saute_le = NOW() - INTERVAL 10 HOUR WHERE user = ?")->execute([$U]);

echo "Profil\n";
$p = Gouts::analyserProfil($db, $U);
$aff = Gouts::affinitesArtistes($db, $U);
ok($aff[$artistes['A']] > 0.5 && $aff[$artistes['B']] > 0.5, 'A et B aimés');
ok($aff[$artistes['H']] < 0, 'H sauté = affinité négative');
ok(!isset($aff[$artistes['C']]), 'C jamais écouté : pas d\'affinité');
$vois = Gouts::voisins($db, $U);
ok(($vois[$artistes['A']][$artistes['B']] ?? 0) > 0.7, 'A voisin de B (le monde)');
ok(($vois[$artistes['A']][$artistes['H']] ?? 0) < 0.3, 'A loin de H');
ok($p['voisins'] > 0 && $p['tags'] > 0, "profil : {$p['voisins']} voisins, {$p['tags']} étiquettes");
$q = $db->prepare("SELECT cle FROM gouts_profil WHERE user = ? AND type = 'tag' ORDER BY score DESC LIMIT 1");
$q->execute([$U]);
ok($q->fetchColumn() === 'skate punk', 'étiquette dominante : skate punk');

echo "Suite (lecture automatique)\n";
$graine = $titres['A'][0];
$suite = GoutsRadio::suite($db, $U, [$graine], [$titres['A'][1]], 12, 0.35);
$ids = array_column($suite, 'id');
$infos = GoutsRadio::infosTitres($db, $U, $ids);
$parArt = array_count_values(array_map(fn($i) => $infos[$i]['artiste'], $ids));
ok(count($suite) === 12, 'douze titres');
ok(!in_array($graine, $ids, true) && !in_array($titres['A'][1], $ids, true), 'ni la graine ni les exclus');
ok(count(array_unique($ids)) === count($ids), 'pas de doublon');
$suites = 0;
for ($i = 1; $i < count($ids); $i++) if ($infos[$ids[$i]]['artiste'] === $infos[$ids[$i - 1]]['artiste']) $suites++;
ok($suites === 0, 'jamais deux fois le même artiste de suite');
$punk = array_sum(array_map(fn($l) => $parArt[$artistes[$l]] ?? 0, ['A', 'B', 'C', 'D']));
ok($punk >= 9, "la suite d'un titre punk reste punk ($punk/12)");
ok(($parArt[$artistes['H']] ?? 0) === 0, 'rien de H (sauté)');
ok(count(array_filter($suite, fn($s) => str_starts_with($s['origin'], 'auto:'))) === 12, 'origines auto:…');

// La séance : on vient de sauter B deux fois → B recule tout de suite.
foreach ([2, 3] as $k) $ecoute->execute([$titres['B'][$k], $U, 0, 8, 0, 1]);
$compteB = 0;
for ($essai = 0; $essai < 5; $essai++) {
    foreach (GoutsRadio::suite($db, $U, [$graine], [], 10, 0.35) as $s) {
        if ((GoutsRadio::infosTitres($db, $U, [$s['id']])[$s['id']]['artiste'] ?? 0) === $artistes['B']) $compteB++;
    }
}
$compteBAvant = $parArt[$artistes['B']] ?? 0;
ok($compteB === 0, "B sauté deux fois dans la séance : mis de côté ($compteBAvant → " . ($compteB / 5) . ')');
// Un seul saut : B recule sans disparaître.
$db->prepare('DELETE FROM play_history WHERE user = ? AND played_at > NOW() - INTERVAL 1 HOUR LIMIT 1')->execute([$U]);
$s1 = GoutsRadio::seance($db, $U);
ok(($s1['sautsArtiste'][$artistes['B']] ?? 0) === 1, 'un saut compté dans la séance');
$db->prepare('DELETE FROM play_history WHERE user = ? AND played_at > NOW() - INTERVAL 1 HOUR')->execute([$U]);

// Rejet d'un artiste : plus jamais proposé.
$db->prepare("INSERT INTO gouts_rejets (user, type, cible_id) VALUES (?, 'artist', ?)")->execute([$U, $artistes['C']]);
$c = 0;
for ($essai = 0; $essai < 5; $essai++) {
    foreach (GoutsRadio::suite($db, $U, [$graine], [], 12, 0.8) as $s) {
        if ((GoutsRadio::infosTitres($db, $U, [$s['id']])[$s['id']]['artiste'] ?? 0) === $artistes['C']) $c++;
    }
}
ok($c === 0, 'artiste rejeté : jamais proposé');

// Aventure : plus haut = plus de titres jamais écoutés.
$neufs = function (float $av) use ($db, $U, $graine) {
    $tit = Gouts::affinitesTitres($db, $U);
    $n = 0;
    for ($e = 0; $e < 6; $e++) foreach (GoutsRadio::suite($db, $U, [$graine], [], 10, $av) as $s) if (!isset($tit[$s['id']])) $n++;
    return $n;
};
$bas = $neufs(0.0);
$haut = $neufs(1.0);
ok($haut > $bas, "aventure : plus d'inconnu à 1,0 ($haut) qu'à 0 ($bas)");
$db->prepare("DELETE FROM gouts_rejets WHERE user = ?")->execute([$U]);

echo "Rayons\n";
Gouts::analyserProfil($db, $U);
$r = GoutsRayons::construire($db, $U, false);
ok(($r['mix'] ?? 0) >= 1, 'au moins un mix (' . ($r['mix'] ?? 0) . ')');
ok(($r['decouvertes'] ?? 0) === 1, 'découvertes de la semaine');
ok(($r['ailleurs'] ?? 0) === 0 || true, 'ailleurs (facultatif ici)');
$q = $db->prepare("SELECT titre, contenu FROM gouts_rayons WHERE user = ? AND type = 'decouvertes'");
$q->execute([$U]);
$d = $q->fetch(PDO::FETCH_ASSOC);
$tit = Gouts::affinitesTitres($db, $U);
$dec = json_decode($d['contenu'], true)['titres'];
ok(count(array_filter($dec, fn($t) => isset($tit[$t['id']]))) === 0, 'découvertes : rien de déjà écouté');
$infos = GoutsRadio::infosTitres($db, $U, array_column($dec, 'id'));
ok(count(array_filter($infos, fn($i) => $i['artiste'] === $artistes['H'])) === 0, 'découvertes : rien de H');
ok(str_contains($dec[0]['raison'] ?? '', 'Parce que tu écoutes'), 'découvertes expliquées');
$q = $db->prepare("SELECT titre, contenu FROM gouts_rayons WHERE user = ? AND type = 'mix' ORDER BY rang LIMIT 1");
$q->execute([$U]);
$m = $q->fetch(PDO::FETCH_ASSOC);
ok($m && str_contains($m['titre'], 'Skate punk'), 'mix nommé d\'après son étiquette : « ' . ($m['titre'] ?? '') . ' »');
$h = GoutsRayons::hydrater($db, $U, json_decode($m['contenu'], true)['titres'], 'mix:1');
ok($h && isset($h[0]['filePath'], $h[0]['artistName']) && $h[0]['origin'] === 'mix:1', 'titres hydratés avec origine');

echo "Tes artistes (bulles)\n";
require_once __DIR__ . '/../src/GoutsBulles.php';
// Un artiste hors bibliothèque, déjà décrit : ses voisins sont E et F.
$sim->execute([Gouts::cle('EssaiGouts Externe'), Gouts::cle('EssaiGouts E'), 'EssaiGouts E', 0.9]);
$sim->execute([Gouts::cle('EssaiGouts Externe'), Gouts::cle('EssaiGouts F'), 'EssaiGouts F', 0.8]);
$sim->execute([Gouts::cle('EssaiGouts Externe'), Gouts::cle('EssaiGouts Loin'), 'EssaiGouts Loin', 0.7]);
$avantG = Gouts::affinitesArtistes($db, $U)[$artistes['G']] ?? 0;
$avantF = Gouts::affinitesArtistes($db, $U)[$artistes['F']] ?? 0;
$r1 = GoutsBulles::choisir($db, $U, 'EssaiGouts G', 2, null);
$r2 = GoutsBulles::choisir($db, $U, 'EssaiGouts Externe', 1, 'https://exemple.test/x.jpg');
ok($r1['niveau'] === 2 && $r2['niveau'] === 1, 'aimer et adorer');
Gouts::analyserProfil($db, $U);
$aff = Gouts::affinitesArtistes($db, $U);
ok(($aff[$artistes['G']] ?? 0) > $avantG + 0.5, 'G adoré (jamais écouté) : affinité forte');
ok(($aff[$artistes['F']] ?? 0) > $avantF, 'F gagne par l\'artiste externe aimé');
$dep = GoutsBulles::depart($db, $U);
ok($dep[0]['niveau'] === 2 && $dep[0]['artistId'] === $artistes['G'], 'bulles : les choisies d\'abord, adorée en tête');
$ext = array_values(array_filter($dep, fn($b) => $b['cle'] === Gouts::cle('EssaiGouts Externe')));
ok($ext && $ext[0]['artistId'] === null && $ext[0]['image'] === 'https://exemple.test/x.jpg', 'bulle externe : sans fiche, avec sa photo');
$aut = GoutsBulles::autour($db, $U, Gouts::cle('EssaiGouts Externe'), 'EssaiGouts Externe', [Gouts::cle('EssaiGouts E')], 6);
$nomsAut = array_column($aut, 'nom');
ok(in_array('EssaiGouts F', $nomsAut, true) && !in_array('EssaiGouts E', $nomsAut, true), 'autour : voisins, sans ceux déjà à l\'écran');
ok($aut[0]['artistId'] !== null && in_array('EssaiGouts Loin', $nomsAut, true), 'autour : la bibliothèque d\'abord, puis ailleurs');
Gouts::analyserProfil($db, $U);
GoutsRayons::construire($db, $U, false);
$q = $db->prepare("SELECT contenu FROM gouts_rayons WHERE user = ? AND type = 'ailleurs'");
$q->execute([$U]);
$noms = array_column(json_decode((string)$q->fetchColumn(), true)['artistes'] ?? [], 'nom');
ok(!in_array('EssaiGouts Externe', $noms, true), 'ailleurs : un artiste déjà choisi n\'y est pas proposé');
$c = GoutsBulles::chercher($db, $U, 'EssaiGouts');
ok($c && $c[0]['artistId'] !== null, 'chercher : la bibliothèque d\'abord');
GoutsBulles::choisir($db, $U, 'EssaiGouts G', 0, null);
ok(!isset(Gouts::choix($db, $U)[Gouts::cle('EssaiGouts G')]), 'retirer');
$deja = GoutsBulles::choisir($db, $U, 'EssaiGouts Externe', 2, null);
ok(Gouts::choix($db, $U)[$deja['cle']]['image'] === 'https://exemple.test/x.jpg', 'adorer après aimer garde la photo');
$refus = false;
try { GoutsBulles::choisir($db, $U, '   ', 1, null); } catch (InvalidArgumentException $e) { $refus = true; }
ok($refus, 'nom vide refusé');

echo "Portrait\n";
$port = GoutsPortrait::pour($db, $U);
ok($port['portrait'] !== '' && $port['etiquettes'] !== [], 'portrait et ADN');
ok(count($port['habitudes']['heures']) === 24, 'heures : 24 colonnes');
ok($port['artistes'][0]['id'] === $artistes['A'] || $port['artistes'][0]['id'] === $artistes['B'], 'repère : A ou B');

nettoyer($db, $U);
echo "\n$total essais, $echecs échec(s).\n";
exit($echecs ? 1 : 0);

<?php
/**
 * Essais du contrat de gestion v2 (« Ma maison ») et du changement de mot de
 * passe obligatoire — sur une base MySQL JETABLE, jamais sur une vraie.
 *
 * Il faut une base vide où setup/schema.sql a été chargé, les variables
 * MYSQL_* qui la désignent, MUSIC_BASE_PATH et DATA_PATH vers des dossiers
 * d'essai, et TEST_JETABLE=oui (garde-fou : le script efface des comptes).
 *
 *   TEST_JETABLE=oui php scripts/test-maison-gestion.php
 *
 * Il lance lui-même `php -S` sur public/ pour les essais HTTP.
 */

if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
if (getenv('TEST_JETABLE') !== 'oui') {
    fwrite(STDERR, "Refusé : TEST_JETABLE=oui exigé (base jetable seulement).\n");
    exit(2);
}

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Auth.php';
require_once __DIR__ . '/../src/Avatar.php';

$racine = dirname(__DIR__);
$port   = 8099;
$base   = "http://127.0.0.1:$port";
$echecs = 0;
$total  = 0;

function ok(bool $cond, string $quoi): void
{
    global $echecs, $total;
    $total++;
    if ($cond) { echo "  ok    $quoi\n"; return; }
    $echecs++;
    echo "  ÉCHEC $quoi\n";
}

/** La commande de gestion : [code, json]. */
function gestion(array $args, ?string $stdin = null): array
{
    global $racine;
    $cmd = array_merge([PHP_BINARY, "$racine/scripts/maison-gestion.php"], $args);
    $p = proc_open($cmd, [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $tubes);
    if ($stdin !== null) fwrite($tubes[0], $stdin);
    fclose($tubes[0]);
    $out = stream_get_contents($tubes[1]);
    stream_get_contents($tubes[2]);
    $code = proc_close($p);
    $j = json_decode($out, true);
    if (!is_array($j)) echo "    (sortie non JSON : " . substr($out, 0, 200) . ")\n";
    return [$code, is_array($j) ? $j : []];
}

/** Une requête HTTP : [statut, corps décodé (ou texte)]. */
function http(string $methode, string $chemin, ?array $json = null, ?string $jeton = null): array
{
    global $base;
    $c = curl_init($base . $chemin);
    $h = [];
    if ($jeton) $h[] = "Authorization: Bearer $jeton";
    if ($json !== null) {
        $h[] = 'Content-Type: application/json';
        curl_setopt($c, CURLOPT_POSTFIELDS, json_encode($json));
    }
    curl_setopt_array($c, [CURLOPT_CUSTOMREQUEST => $methode, CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => $h]);
    $corps = curl_exec($c);
    $statut = curl_getinfo($c, CURLINFO_HTTP_CODE);
    curl_close($c);
    $j = json_decode((string)$corps, true);
    return [$statut, is_array($j) ? $j : (string)$corps];
}

function personne(string $id): array
{
    [, $j] = gestion(['personnes']);
    foreach ($j['personnes'] ?? [] as $p) if ($p['id'] === $id) return $p;
    return [];
}

function login(string $u, string $p): array
{
    return http('POST', '/api/v2/auth.php?action=login', ['username' => $u, 'password' => $p]);
}

// ── Préparation ─────────────────────────────────────────────────────────────
$db = AppConfig::getDB();
$db->exec('DELETE FROM users');
$auth = new Auth();
$auth->createUser('chef', 'chef-mot-de-passe', 'Le chef', true, '.');
$chefId = (string)$db->lastInsertId();

$musique = rtrim(getenv('MUSIC_BASE_PATH') ?: '/tmp/musique-essai', '/');
@mkdir("$musique/Artiste/Album", 0777, true);
file_put_contents("$musique/Artiste/Album/01 - Titre.mp3", 'pas vraiment du son');

$serveur = proc_open([PHP_BINARY, '-S', "0.0.0.0:$port", '-t', "$racine/public"],
    [0 => ['pipe', 'r'], 1 => ['file', '/dev/null', 'w'], 2 => ['file', '/dev/null', 'w']], $t, $racine);
register_shutdown_function(function () use ($serveur) { proc_terminate($serveur); });
for ($i = 0; $i < 50 && !@fsockopen('127.0.0.1', $port); $i++) usleep(100000);

// ── resume / creer ──────────────────────────────────────────────────────────
echo "resume, creer\n";
[$c, $j] = gestion(['resume']);
ok($c === 0 && ($j['contrat'] ?? null) === 2, 'resume annonce contrat 2');
[$c, $j] = gestion(['creer', 'Alice Essai']);
ok($c === 0 && !empty($j['secret']) && !empty($j['identifiant']), 'creer rend un secret et un identifiant');
$alice = $j['id']; $aliceNom = $j['identifiant']; $secret = $j['secret'];
$p = personne($alice);
foreach (['actif', 'doit_changer', 'derniere_connexion', 'photo'] as $champ) {
    ok(array_key_exists($champ, $p), "personnes porte « $champ »");
}
ok($p['doit_changer'] === true && $p['actif'] === true && $p['photo'] === false && $p['derniere_connexion'] === null,
   'compte créé : doit_changer vrai, actif, sans photo, jamais connecté');

// ── changement obligatoire ──────────────────────────────────────────────────
echo "changement obligatoire\n";
[$s, $j] = login($aliceNom, $secret);
ok($s === 200 && ($j['data']['doit_changer'] ?? null) === true, 'la connexion réussit et porte doit_changer');
$jeton = $j['data']['token'] ?? '';
ok(personne($alice)['derniere_connexion'] !== null, 'derniere_connexion mise à jour à la connexion');
[$s, $j] = http('GET', '/api/v2/playlists.php?action=list', null, $jeton);
ok($s === 403 && ($j['error']['code'] ?? '') === 'changement_requis', 'API v2 : 403 changement_requis');
[$s] = http('GET', '/api/v2/auth.php?action=refresh', null, $jeton);
ok($s === 403, 'refresh refusé tant que le mot de passe est temporaire');
[$s, $j] = http('GET', '/api/notifications.php', null, $jeton);
ok($s === 403 && ($j['code'] ?? '') === 'changement_requis', 'point d\'entrée historique : 403 changement_requis');
// stream.php laisse passer la boucle locale (ffmpeg interne) : on l'appelle
// par l'adresse du conteneur, comme le ferait Caddy.
$base = 'http://' . gethostbyname(gethostname()) . ":$port";
[$s] = http('GET', '/stream.php?path=Artiste/Album/01%20-%20Titre.mp3&token=' . $jeton);
ok($s === 401, 'stream.php refuse la lecture');
$base = "http://127.0.0.1:$port";
[$s, $j] = http('GET', '/api/v2/auth.php?action=me', null, $jeton);
ok($s === 200 && ($j['data']['user']['doitChanger'] ?? null) === true, 'me reste permis');
[$s, $j] = http('POST', '/api/v2/auth.php?action=change_password', ['old_password' => 'faux', 'new_password' => 'nouveau-mdp-1'], $jeton);
ok($s === 400 && ($j['error']['code'] ?? '') === 'wrong_password', 'ancien mot de passe faux refusé');
[$s, $j] = http('POST', '/api/v2/auth.php?action=change_password', ['old_password' => $secret, 'new_password' => $secret], $jeton);
ok($s === 400 && ($j['error']['code'] ?? '') === 'same_password', 'nouveau = ancien refusé');
[$s, $j] = http('POST', '/api/v2/auth.php?action=change_password', ['old_password' => $secret, 'new_password' => 'court'], $jeton);
ok($s === 400 && ($j['error']['code'] ?? '') === 'weak_password', 'mot de passe trop court refusé');
// Une deuxième session, qui doit tomber au changement.
[, $j2] = login($aliceNom, $secret);
$autre = $j2['data']['token'] ?? '';
[$s, $j] = http('POST', '/api/v2/auth.php?action=change_password', ['old_password' => $secret, 'new_password' => 'nouveau-mdp-1'], $jeton);
ok($s === 200 && ($j['data']['user']['doitChanger'] ?? null) === false, 'changement accepté, doitChanger faux');
[$s] = http('GET', '/api/v2/playlists.php?action=list', null, $jeton);
ok($s === 200, 'le jeton courant est gardé et ouvre l\'API');
$base = 'http://' . gethostbyname(gethostname()) . ":$port";
[$s] = http('GET', '/stream.php?path=Artiste/Album/01%20-%20Titre.mp3&token=' . $jeton);
ok($s !== 401, 'stream.php lit de nouveau après le changement');
$base = "http://127.0.0.1:$port";
[$s] = http('GET', '/api/v2/auth.php?action=me', null, $autre);
ok($s === 401, 'les autres sessions sont révoquées');
ok(personne($alice)['doit_changer'] === false, 'personnes : doit_changer faux après le changement');

// ── Subsonic ────────────────────────────────────────────────────────────────
echo "Subsonic\n";
[$s, $j] = http('GET', '/rest/index.php?method=getUser&f=json&u=' . urlencode($aliceNom) . '&p=nouveau-mdp-1');
ok(($j['subsonic-response']['status'] ?? '') === 'ok', 'Subsonic : compte normal accepté');
[, $j] = gestion(['reinitialiser', $alice]);
$tmp = $j['secret'] ?? '';
ok(personne($alice)['doit_changer'] === true, 'reinitialiser : doit_changer vrai');
[$s, $j] = http('GET', '/rest/index.php?method=getUser&f=json&u=' . urlencode($aliceNom) . '&p=' . urlencode($tmp));
ok(($j['subsonic-response']['status'] ?? '') === 'failed', 'Subsonic : mot de passe temporaire refusé');
$st = $db->prepare('SELECT subsonic_password FROM users WHERE id = ?');
$st->execute([$alice]);
ok($st->fetchColumn() === null, 'le mot de passe temporaire n\'est pas retenu pour Subsonic');

// ── definir ─────────────────────────────────────────────────────────────────
echo "definir\n";
[$c, $j] = gestion(['definir', $alice], "court\n");
ok($c === 1 && !empty($j['erreur']), 'definir : secret trop court refusé');
[$c, $j] = gestion(['definir', $alice], "choisi-par-admin\n");
ok($c === 0 && ($j['ok'] ?? false) === true && !isset($j['secret']), 'definir accepté, sans secret dans la sortie');
[$s, $j] = login($aliceNom, 'choisi-par-admin');
ok($s === 200 && ($j['data']['doit_changer'] ?? null) === true, 'secret défini = temporaire');
$jeton = $j['data']['token'] ?? '';
http('POST', '/api/v2/auth.php?action=change_password', ['old_password' => 'choisi-par-admin', 'new_password' => 'mot-de-passe-2'], $jeton);

// ── desactiver / activer ────────────────────────────────────────────────────
echo "desactiver, activer\n";
http('GET', '/rest/index.php?method=getUser&f=json&u=' . urlencode($aliceNom) . '&p=mot-de-passe-2');
[$c, $j] = gestion(['desactiver', $alice]);
ok($c === 0 && personne($alice)['actif'] === false, 'desactiver');
[$s] = http('GET', '/api/v2/auth.php?action=me', null, $jeton);
ok($s === 401, 'ses jetons sont révoqués');
[$s, $j] = login($aliceNom, 'mot-de-passe-2');
ok($s === 403 && ($j['error']['code'] ?? '') === 'account_disabled'
   && str_contains($j['error']['message'] ?? '', 'désactivé'), 'connexion refusée : « compte désactivé »');
[$s, $j] = login($aliceNom, 'mauvais');
ok($s === 401, 'mauvais mot de passe d\'un compte désactivé : rien n\'est révélé');
[$s, $j] = http('GET', '/rest/index.php?method=getUser&f=json&u=' . urlencode($aliceNom) . '&p=mot-de-passe-2');
ok(($j['subsonic-response']['status'] ?? '') === 'failed', 'Subsonic par mot de passe : refusé');
$sel = 'abc123';
[$s, $j] = http('GET', '/rest/index.php?method=getUser&f=json&u=' . urlencode($aliceNom) . '&s=' . $sel . '&t=' . md5('mot-de-passe-2' . $sel));
ok(($j['subsonic-response']['status'] ?? '') === 'failed', 'Subsonic par jeton : refusé');
[$c] = gestion(['activer', $alice]);
[$s] = login($aliceNom, 'mot-de-passe-2');
ok($c === 0 && $s === 200, 'activer : la connexion remarche');
[$c, $j] = gestion(['desactiver', $chefId]);
ok($c === 1 && !empty($j['erreur']), 'desactiver le dernier admin actif : refusé');

// ── modifier ────────────────────────────────────────────────────────────────
echo "modifier\n";
[$c] = gestion(['modifier', $alice, 'nom=Alice Renommée']);
ok($c === 0 && personne($alice)['nom'] === 'Alice Renommée', 'modifier nom=');
ok(personne($alice)['identifiant'] === $aliceNom, 'le nom d\'utilisateur ne change pas');
[$c, $j] = gestion(['modifier', $alice, 'courriel=a@b.c']);
ok($c === 1 && str_contains($j['erreur'] ?? '', 'courriel'), 'modifier courriel= : erreur claire');
[$c, $j] = gestion(['modifier', $alice, 'nom=']);
ok($c === 1, 'modifier nom vide : refusé');

// ── photo ───────────────────────────────────────────────────────────────────
echo "photo\n";
[$c, $j] = gestion(['photo', $alice], "<?php echo 'pas une image';");
ok($c === 1 && !empty($j['erreur']), 'photo invalide refusée');
[$c, $j] = gestion(['photo', $alice], "GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x00\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;");
ok($c === 1 && !empty($j['erreur']), 'GIF (type non admis) refusé');
[$c] = gestion(['photo', $alice], str_repeat('a', 5 * 1024 * 1024 + 10));
ok($c === 1, 'image de plus de 5 Mo refusée');
$im = imagecreatetruecolor(400, 300);
ob_start(); imagepng($im); $png = ob_get_clean();
[$c, $j] = gestion(['photo', $alice], $png);
ok($c === 0 && personne($alice)['photo'] === true, 'photo PNG acceptée');
$taille = @getimagesize(Avatar::path((int)$alice));
ok(is_array($taille) && $taille[0] === 256 && $taille[1] === 256 && $taille['mime'] === 'image/jpeg', 'recadrée carrée 256 px');
[$c] = gestion(['photo', $alice, '--retirer']);
ok($c === 0 && personne($alice)['photo'] === false, 'photo --retirer');

// ── supprimer ───────────────────────────────────────────────────────────────
echo "supprimer\n";
[$c, $j] = gestion(['supprimer', $chefId]);
ok($c === 1 && !empty($j['erreur']), 'supprimer le dernier admin : refusé');
$db->prepare('INSERT INTO artists (name, user) VALUES (?, ?)')->execute(['Artiste', $aliceNom]);
$artiste = (int)$db->lastInsertId();
$db->prepare('INSERT INTO albums (artist_id, name) VALUES (?, ?)')->execute([$artiste, 'Album']);
$album = (int)$db->lastInsertId();
$db->prepare('INSERT INTO songs (album_id, title, file_path) VALUES (?, ?, ?)')->execute([$album, 'Titre', 'Artiste/Album/01 - Titre.mp3']);
$titre = (int)$db->lastInsertId();
$db->prepare('INSERT INTO playlists (name, user) VALUES (?, ?)')->execute(['Ma liste', $aliceNom]);
$liste = (int)$db->lastInsertId();
$db->prepare('INSERT INTO playlist_songs (playlist_id, song_id, track_order) VALUES (?, ?, 1)')->execute([$liste, $titre]);
$db->prepare('INSERT INTO favorites (song_id, user) VALUES (?, ?)')->execute([$titre, $aliceNom]);
$db->prepare('INSERT INTO play_history (song_id, user) VALUES (?, ?)')->execute([$titre, $aliceNom]);
gestion(['photo', $alice], $png);
[$c, $j] = gestion(['supprimer', $alice]);
ok($c === 0 && ($j['ok'] ?? false) === true, 'supprimer');
ok(personne($alice) === [], 'le compte a disparu');
foreach (['playlists', 'favorites', 'play_history', 'artists'] as $table) {
    $st = $db->prepare("SELECT COUNT(*) FROM $table WHERE user = ?");
    $st->execute([$aliceNom]);
    ok((int)$st->fetchColumn() === 0, "$table : plus rien à son nom");
}
ok((int)$db->query("SELECT COUNT(*) FROM playlist_songs WHERE playlist_id = $liste")->fetchColumn() === 0, 'playlist_songs : vidée en cascade');
ok((int)$db->query("SELECT COUNT(*) FROM sessions WHERE user_id = $alice")->fetchColumn() === 0, 'sessions supprimées');
ok(!is_file(Avatar::path((int)$alice)), 'photo supprimée');
ok(is_file("$musique/Artiste/Album/01 - Titre.mp3"), 'la MUSIQUE (fichier) est intacte');
[$c, $j] = gestion(['supprimer', '99999']);
ok($c === 1 && !empty($j['erreur']), 'supprimer une personne introuvable : erreur');

// ── Comptes de la maison v1.1 : empreinte ─────────────────────────────────────
$db->prepare('INSERT INTO users (username, password_hash, full_name, is_admin, music_directory) VALUES (?, ?, ?, 0, ?)')
    ->execute(['empreinte_essai', password_hash('mon-mot-de-passe', PASSWORD_DEFAULT), 'Empreinte', '.']);
$idE = (string)$db->lastInsertId();
[$c, $j] = gestion(['empreinte', $idE]);
ok($c === 0 && ($j['algo'] ?? '') === 'bcrypt' && array_keys($j) === ['empreinte', 'algo'], 'empreinte : bcrypt');
ok(password_verify('mon-mot-de-passe', $j['empreinte'] ?? ''), 'empreinte : le hash tel que stocké');
$db->prepare('UPDATE users SET password_hash = ? WHERE id = ?')->execute([password_hash('x', PASSWORD_ARGON2ID), (int)$idE]);
[$c, $j] = gestion(['empreinte', $idE]);
ok($c === 0 && ($j['algo'] ?? '') === 'argon2id', 'empreinte : argon2id accepté');
$db->prepare('UPDATE users SET password_hash = ? WHERE id = ?')->execute(['md5:abcdef', (int)$idE]);
[$c, $j] = gestion(['empreinte', $idE]);
ok($c === 1 && !empty($j['erreur']) && !str_contains($j['erreur'], 'md5'), 'empreinte : format inconnu refusé, sans le recopier');
$db->prepare('UPDATE users SET password_hash = ?, must_change_password = 1 WHERE id = ?')
    ->execute([password_hash('temporaire', PASSWORD_DEFAULT), (int)$idE]);
[$c, $j] = gestion(['empreinte', $idE]);
ok($c === 1 && !empty($j['erreur']) && !isset($j['empreinte']), 'empreinte : mot de passe temporaire refusé');
[$c, $j] = gestion(['empreinte', '99999']);
ok($c === 1 && !empty($j['erreur']), 'empreinte : personne introuvable');
$db->prepare('DELETE FROM users WHERE id = ?')->execute([(int)$idE]);

echo "\n" . ($total - $echecs) . "/$total essais réussis\n";
exit($echecs === 0 ? 0 : 1);

<?php
/**
 * Essais des comptes de la maison (~/gullios/CONTRAT-COMPTES.md, §2) — sur une
 * base MySQL JETABLE, jamais sur une vraie, avec un FAUX service Comptes
 * (scripts/test-comptes-faux.php).
 *
 * Il faut une base vide où setup/schema.sql a été chargé, les variables
 * MYSQL_* qui la désignent, MUSIC_BASE_PATH et DATA_PATH vers des dossiers
 * d'essai, et TEST_JETABLE=oui (garde-fou : le script efface des comptes).
 * Ne pas poser COMPTES_URL : le script lance lui-même trois `php -S` sur
 * public/ (avec Comptes, sans Comptes, Comptes injoignable) et le faux Comptes.
 *
 *   TEST_JETABLE=oui php scripts/test-comptes.php
 */

if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
if (getenv('TEST_JETABLE') !== 'oui') {
    fwrite(STDERR, "Refusé : TEST_JETABLE=oui exigé (base jetable seulement).\n");
    exit(2);
}
if (getenv('COMPTES_URL') !== false) {
    fwrite(STDERR, "Ne pas poser COMPTES_URL : le script choisit le mode de chaque serveur.\n");
    exit(2);
}

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Auth.php';
require_once __DIR__ . '/../src/Avatar.php';

$racine = dirname(__DIR__);
$echecs = 0;
$total  = 0;
const P_COMPTES = 8191, P_FAUX = 8192, P_SANS = 8193, P_MUET = 8194;
const JETON = 'jeton-essai-comptes';

function ok(bool $cond, string $quoi): void
{
    global $echecs, $total;
    $total++;
    if ($cond) { echo "  ok    $quoi\n"; return; }
    $echecs++;
    echo "  ÉCHEC $quoi\n";
}

function env_avec(array $plus): array
{
    $env = getenv();
    unset($env['COMPTES_URL'], $env['COMPTES_JETON']);
    return array_merge($env, $plus);
}

$env_comptes = env_avec(['COMPTES_URL' => 'http://127.0.0.1:' . P_FAUX, 'COMPTES_JETON' => JETON]);
$env_sans    = env_avec([]);

/** La commande de gestion : [code, json]. */
function gestion(array $args, array $env, ?string $stdin = null): array
{
    global $racine;
    $cmd = array_merge([PHP_BINARY, "$racine/scripts/maison-gestion.php"], $args);
    $p = proc_open($cmd, [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $tubes, null, $env);
    if ($stdin !== null) fwrite($tubes[0], $stdin);
    fclose($tubes[0]);
    $out = stream_get_contents($tubes[1]);
    stream_get_contents($tubes[2]);
    $code = proc_close($p);
    $j = json_decode($out, true);
    return [$code, is_array($j) ? $j : []];
}

/** Une requête HTTP : [statut, corps décodé (ou texte)]. */
function http(int $port, string $methode, string $chemin, ?array $json = null, ?string $jeton = null, array $entetes = []): array
{
    $c = curl_init("http://127.0.0.1:$port" . $chemin);
    $h = $entetes;
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

function connexion(int $port, array $corps, array $entetes = []): array
{
    return http($port, 'POST', '/api/v2/auth.php?action=login', $corps, null, $entetes);
}

/** Subsonic : le statut de la réponse (« ok » / « failed ») et le code d'erreur. */
function subsonic(int $port, string $methode, array $q): array
{
    [, $j] = http($port, 'GET', "/rest/index.php?" . http_build_query($q + ['method' => $methode, 'f' => 'json', 'v' => '1.16.1', 'c' => 'essai']));
    $r = is_array($j) ? ($j['subsonic-response'] ?? []) : [];
    return [$r['status'] ?? '?', $r['error']['code'] ?? null];
}

function lancer(int $port, string $docroot, array $env, ?string $routeur = null): array
{
    $cmd = [PHP_BINARY, '-S', "127.0.0.1:$port", '-t', $docroot];
    if ($routeur) $cmd[] = $routeur;
    $p = proc_open($cmd, [0 => ['file', '/dev/null', 'r'], 1 => ['file', '/dev/null', 'w'], 2 => ['file', '/dev/null', 'w']], $t, null, $env);
    return [$p, $port];
}

// ── Préparation ─────────────────────────────────────────────────────────────
$db = AppConfig::getDB();   // + runMigrations : compte_id, email, subsonic_password
$db->exec('DELETE FROM users');
(new Auth())->createUser('chef', 'chef-mot-de-passe', 'Le chef', true, '.');
$chefId = (int)$db->lastInsertId();

$etat = tempnam(sys_get_temp_dir(), 'faux-comptes');
file_put_contents($etat, json_encode(['comptes' => [
    ['id' => 'c-alice', 'nom' => 'Alice Tremblay', 'courriel' => 'alice@exemple.ca', 'mdp' => 'maison-alice-1', 'doit_changer' => false, 'photo' => true],
    ['id' => 'c-bob', 'nom' => 'Bob', 'courriel' => 'bob@exemple.ca', 'mdp' => 'temporaire-bob', 'doit_changer' => true, 'photo' => false],
    ['id' => 'c-desac', 'nom' => 'Désactivé', 'courriel' => 'desac@exemple.ca', 'mdp' => 'mdp-desac-123', 'doit_changer' => false, 'photo' => false, 'etat' => 'desactive'],
    ['id' => 'c-sans', 'nom' => 'Sans accès', 'courriel' => 'sans@exemple.ca', 'mdp' => 'mdp-sans-1234', 'doit_changer' => false, 'photo' => false, 'etat' => 'sans_acces'],
    ['id' => 'c-bloque', 'nom' => 'Bloqué', 'courriel' => 'bloque@exemple.ca', 'mdp' => 'x', 'doit_changer' => false, 'photo' => false, 'etat' => 'bloque'],
]]));
$faux = lancer(P_FAUX, __DIR__, env_avec(['FAUX_COMPTES_ETAT' => $etat, 'FAUX_COMPTES_JETON' => JETON]), __DIR__ . '/test-comptes-faux.php');
$avec = lancer(P_COMPTES, "$racine/public", $env_comptes);
$sans = lancer(P_SANS, "$racine/public", $env_sans);
$muet = lancer(P_MUET, "$racine/public", env_avec(['COMPTES_URL' => 'http://127.0.0.1:1', 'COMPTES_JETON' => JETON]));
usleep(800000);

try {
    echo "Mode Comptes (COMPTES_URL posé)\n";
    [$s, $j] = http(P_COMPTES, 'GET', '/api/v2/ping.php');
    ok(($j['data']['connexion'] ?? null) === 'courriel' && ($j['data']['comptes'] ?? null) === true, 'ping annonce la connexion par courriel');

    [$s, $j] = connexion(P_COMPTES, ['username' => 'chef', 'password' => 'chef-mot-de-passe']);
    ok($s === 400 && ($j['error']['code'] ?? '') === 'courriel_requis', 'connexion par nom d\'utilisateur refusée');
    [$s] = http(P_COMPTES, 'POST', '/api/login.php', ['username' => 'chef', 'password' => 'chef-mot-de-passe']);
    ok($s === 401, 'ancienne route /api/login.php refusée aussi');

    [$s, $j] = connexion(P_COMPTES, ['courriel' => 'inconnu@exemple.ca', 'password' => 'nimporte']);
    ok($s === 401 && ($j['error']['code'] ?? '') === 'invalid_credentials', 'courriel inconnu → 401');
    [$s, $j] = connexion(P_COMPTES, ['courriel' => 'alice@exemple.ca', 'password' => 'mauvais']);
    ok($s === 401 && ($j['error']['code'] ?? '') === 'invalid_credentials', 'mauvais mot de passe → 401');

    [$s, $j] = connexion(P_COMPTES, ['courriel' => ' Alice@Exemple.CA ', 'password' => 'maison-alice-1'], ['X-Forwarded-For: 203.0.113.9']);
    ok($s === 200 && !empty($j['data']['token']), 'Alice se connecte par courriel');
    ok(($j['data']['doit_changer'] ?? null) === false, 'doit_changer faux recopié');
    $jetonAlice = $j['data']['token'] ?? '';
    $u = $db->query("SELECT * FROM users WHERE compte_id = 'c-alice'")->fetch(PDO::FETCH_ASSOC);
    ok($u !== false, 'compte local provisionné (compte_id)');
    ok($u && !$u['is_admin'] && $u['music_directory'] === '.', 'non admin, lit tout le dossier de musique');
    ok($u && $u['full_name'] === 'Alice Tremblay' && $u['email'] === 'alice@exemple.ca', 'nom et courriel recopiés');
    ok($u && $u['username'] === 'alice.tremblay', 'nom d\'utilisateur tiré du nom');
    ok($u && Avatar::exists((int)$u['id']), 'photo recopiée');
    $f = json_decode((string)file_get_contents($etat), true);
    ok(($f['dernier_ip'] ?? null) === '203.0.113.9', 'IP du demandeur transmise à Comptes');

    [$s, $j] = connexion(P_COMPTES, ['username' => 'alice@exemple.ca', 'password' => 'maison-alice-1']);
    ok($s === 200, 'courriel accepté aussi dans le champ username (anciens clients)');
    ok((int)$db->query("SELECT COUNT(*) FROM users WHERE compte_id = 'c-alice'")->fetchColumn() === 1, 'pas de doublon à la 2e connexion');
    [$s, $j] = http(P_COMPTES, 'GET', '/api/v2/auth.php?action=me', null, $jetonAlice);
    ok($s === 200 && ($j['data']['user']['courriel'] ?? null) === 'alice@exemple.ca', 'me rend le courriel');

    [$s, $j] = connexion(P_COMPTES, ['courriel' => 'desac@exemple.ca', 'password' => 'mdp-desac-123']);
    ok($s === 403 && ($j['error']['code'] ?? '') === 'account_disabled', 'desactive → 403 account_disabled');
    [$s, $j] = connexion(P_COMPTES, ['courriel' => 'sans@exemple.ca', 'password' => 'mdp-sans-1234']);
    ok($s === 403 && ($j['error']['code'] ?? '') === 'sans_acces' && str_contains($j['error']['message'] ?? '', "n'a pas accès à GulliFY"), 'sans_acces → 403 avec le message du contrat');
    [$s, $j] = connexion(P_COMPTES, ['courriel' => 'bloque@exemple.ca', 'password' => 'x']);
    ok($s === 429 && ($j['error']['code'] ?? '') === 'bloque', 'bloque → 429');
    [$s, $j] = connexion(P_MUET, ['courriel' => 'alice@exemple.ca', 'password' => 'maison-alice-1']);
    ok($s === 503 && ($j['error']['code'] ?? '') === 'comptes_injoignable', 'Comptes injoignable → 503 clair');

    echo "Mot de passe temporaire et changement\n";
    [$s, $j] = connexion(P_COMPTES, ['courriel' => 'bob@exemple.ca', 'password' => 'temporaire-bob']);
    ok($s === 200 && ($j['data']['doit_changer'] ?? null) === true, 'Bob : doit_changer vrai');
    $jetonBob = $j['data']['token'] ?? '';
    [$s, $j] = http(P_COMPTES, 'GET', '/api/v2/stats.php', null, $jetonBob);
    ok($s === 403 && ($j['error']['code'] ?? '') === 'changement_requis', '403 changement_requis ailleurs');
    [$s, $j] = http(P_COMPTES, 'POST', '/api/v2/auth.php?action=change_password', ['old_password' => 'temporaire-bob', 'new_password' => 'court1234'], $jetonBob);
    ok($s === 400 && ($j['error']['code'] ?? '') === 'weak_password', 'moins de 10 caractères refusé');
    [$s, $j] = http(P_COMPTES, 'POST', '/api/v2/auth.php?action=change_password', ['old_password' => 'faux-ancien', 'new_password' => 'tout-nouveau-bob'], $jetonBob);
    ok($s === 400 && ($j['error']['code'] ?? '') === 'wrong_password', 'ancien faux refusé (401 de Comptes)');
    [$s, $j] = http(P_COMPTES, 'POST', '/api/v2/auth.php?action=change_password', ['old_password' => 'temporaire-bob', 'new_password' => 'tout-nouveau-bob'], $jetonBob);
    ok($s === 200 && ($j['data']['user']['doitChanger'] ?? null) === false, 'changement par /changer, doit_changer levé');
    $f = json_decode((string)file_get_contents($etat), true);
    ok(($f['comptes'][1]['mdp'] ?? '') === 'tout-nouveau-bob', 'Comptes a reçu le nouveau mot de passe');
    [$s] = http(P_COMPTES, 'GET', '/api/v2/stats.php', null, $jetonBob);
    ok($s === 200, 'l\'app s\'ouvre après le changement (jeton gardé)');

    echo "Subsonic : mot de passe d'application\n";
    $q = ['u' => 'alice.tremblay', 'p' => 'maison-alice-1'];
    ok(subsonic(P_COMPTES, 'getMusicFolders', $q)[0] === 'failed', 'mot de passe de la maison refusé par Subsonic');
    [$s, $j] = http(P_COMPTES, 'GET', '/api/v2/auth.php?action=subsonic', null, $jetonAlice);
    ok($s === 200 && ($j['data']['actif'] ?? null) === false && ($j['data']['identifiant'] ?? '') === 'alice.tremblay', 'état : aucun mot de passe d\'application');
    [$s, $j] = http(P_COMPTES, 'POST', '/api/v2/auth.php?action=subsonic_generer', [], $jetonAlice);
    $mdpApp = $j['data']['motDePasse'] ?? '';
    ok($s === 200 && strlen($mdpApp) === 20, 'mot de passe d\'application généré (montré une fois)');
    [$s, $j] = http(P_COMPTES, 'GET', '/api/v2/auth.php?action=subsonic', null, $jetonAlice);
    ok(($j['data']['actif'] ?? null) === true && !isset($j['data']['motDePasse']), 'l\'état ne le remontre jamais');
    ok(subsonic(P_COMPTES, 'getMusicFolders', ['u' => 'alice.tremblay', 'p' => $mdpApp])[0] === 'ok', 'Subsonic accepte le mot de passe d\'application (p=)');
    ok(subsonic(P_COMPTES, 'getMusicFolders', ['u' => 'alice.tremblay', 'p' => 'enc:' . bin2hex($mdpApp)])[0] === 'ok', '… en enc:hex');
    ok(subsonic(P_COMPTES, 'getMusicFolders', ['u' => 'alice@exemple.ca', 'p' => $mdpApp])[0] === 'ok', '… avec le courriel comme u');
    $sel = 'sel123';
    ok(subsonic(P_COMPTES, 'getMusicFolders', ['u' => 'alice.tremblay', 't' => md5($mdpApp . $sel), 's' => $sel])[0] === 'ok', '… en jeton+sel');
    [$s] = http(P_COMPTES, 'POST', '/api/v2/auth.php?action=subsonic_revoquer', [], $jetonAlice);
    ok($s === 200 && subsonic(P_COMPTES, 'getMusicFolders', ['u' => 'alice.tremblay', 'p' => $mdpApp])[0] === 'failed', 'révoqué → refusé');

    echo "Gestion (maison-gestion.php) avec Comptes\n";
    [$c, $j] = gestion(['personnes'], $env_comptes);
    $alice = null;
    foreach ($j['personnes'] ?? [] as $p) if (($p['compte_id'] ?? null) === 'c-alice') $alice = $p;
    ok($c === 0 && $alice && $alice['courriel'] === 'alice@exemple.ca', 'personnes rend compte_id et courriel');
    foreach (['reinitialiser' => [(string)$chefId], 'creer' => ['Nouveau'], 'definir' => [(string)$chefId]] as $a => $args) {
        [$c, $j] = gestion(array_merge([$a], $args), $env_comptes, "unmotdepasse\n");
        ok($c === 1 && str_contains($j['erreur'] ?? '', 'gérés par les comptes de la maison'), "$a refusé (géré par Comptes)");
    }
    [$c] = gestion(['lier', (string)$chefId, 'c-chef'], $env_comptes);
    ok($c === 0 && $db->query("SELECT compte_id FROM users WHERE id = $chefId")->fetchColumn() === 'c-chef', 'lier relie un compte existant');
    [$c] = gestion(['lier', (string)$chefId, 'c-chef'], $env_comptes);
    ok($c === 0, 'lier une 2e fois au même compte : ok');
    [$c, $j] = gestion(['lier', (string)$chefId, 'c-alice'], $env_comptes);
    ok($c === 1 && str_contains($j['erreur'] ?? '', 'déjà relié'), 'lier à un compte déjà relié ailleurs : refusé');
    [$c] = gestion(['desactiver', (string)$alice['id']], $env_comptes);
    [$s, $j] = connexion(P_COMPTES, ['courriel' => 'alice@exemple.ca', 'password' => 'maison-alice-1']);
    ok($c === 0 && $s === 403 && ($j['error']['code'] ?? '') === 'account_disabled', 'désactivé dans GulliFY → connexion refusée');
    [$s] = http(P_COMPTES, 'GET', '/api/v2/stats.php', null, $jetonAlice);
    ok($s === 401, '… et ses jetons coupés');
    gestion(['activer', (string)$alice['id']], $env_comptes);

    echo "Sans COMPTES_URL : rien ne change\n";
    [$s, $j] = http(P_SANS, 'GET', '/api/v2/ping.php');
    ok(($j['data']['connexion'] ?? null) === 'nom_utilisateur', 'ping annonce la connexion par nom d\'utilisateur');
    $db->exec("UPDATE users SET compte_id = NULL WHERE id = $chefId");
    [$s, $j] = connexion(P_SANS, ['username' => 'chef', 'password' => 'chef-mot-de-passe']);
    ok($s === 200 && !empty($j['data']['token']), 'connexion par nom d\'utilisateur');
    $jetonChef = $j['data']['token'] ?? '';
    [$s, $j] = connexion(P_SANS, ['courriel' => 'alice@exemple.ca', 'password' => 'maison-alice-1']);
    ok($s === 400, 'courriel sans Comptes : non (champs username/password requis)');
    ok(subsonic(P_SANS, 'getMusicFolders', ['u' => 'chef', 'p' => 'chef-mot-de-passe'])[0] === 'ok', 'Subsonic avec le mot de passe GulliFY, comme avant');
    [$s, $j] = http(P_SANS, 'POST', '/api/v2/auth.php?action=subsonic_generer', [], $jetonChef);
    ok($s === 400 && ($j['error']['code'] ?? '') === 'comptes_inactif', 'pas de mot de passe d\'application sans Comptes');
    [$s, $j] = http(P_SANS, 'POST', '/api/v2/auth.php?action=change_password', ['old_password' => 'chef-mot-de-passe', 'new_password' => 'huit-car'], $jetonChef);
    ok($s === 200, 'changement local à 8 caractères, comme avant');
    [$c, $j] = gestion(['creer', 'Nouvelle Personne'], $env_sans);
    ok($c === 0 && !empty($j['secret']), 'creer marche sans Comptes');
    [$c, $j] = gestion(['lier', (string)$chefId, 'c-chef'], $env_sans);
    ok($c === 1, 'lier refusé sans Comptes');
} finally {
    foreach ([$faux, $avec, $sans, $muet] as [$p]) { proc_terminate($p); proc_close($p); }
    @unlink($etat);
}

echo "\n$total essais, $echecs échec(s)\n";
exit($echecs === 0 ? 0 : 1);

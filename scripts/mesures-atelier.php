<?php
/**
 * Les mesures de l'atelier (page Réseau de l'app Atelier) : gullify.app vu d'ici, une minute à la fois,
 * rangé comme les maisons (MesuresMaisons, maison « atelier »). Lancé chaque minute par cron sur l'atelier :
 *   docker exec gullify php /app/scripts/mesures-atelier.php
 * Et l'historique de toutes les maisons et de leurs postes, pour la page Réseau :
 *   docker exec gullify php /app/scripts/mesures-atelier.php historique 24h   → JSON {periode, maisons: {nom: …}}
 * Les mesures se prennent DANS le conteneur gullify (le chemin vers gullify.app passe par l'hôte).
 */
declare(strict_types=1);

require_once __DIR__ . '/../src/MesuresMaisons.php';

const NOM_ATELIER = 'atelier';
const PERIODES = ['6h', '24h', '7j', '30j', '1an'];

/** Temps pour ouvrir une connexion TCP (ms), sans compter la résolution du nom ; null si ça échoue. */
function latence(string $hote, int $port): ?float
{
    $ip = filter_var($hote, FILTER_VALIDATE_IP) ? $hote : gethostbyname($hote);
    if ($ip === $hote && !filter_var($hote, FILTER_VALIDATE_IP)) {
        return null;
    }
    $debut = microtime(true);
    $socket = @stream_socket_client("tcp://$ip:$port", $n, $err, 5);
    if (!$socket) {
        return null;
    }
    fclose($socket);
    return round((microtime(true) - $debut) * 1000, 1);
}

/** 1 si le site répond (code HTTP < 500), 0 sinon. */
function disponible(string $url): int
{
    $contexte = stream_context_create(['http' => ['method' => 'HEAD', 'timeout' => 8, 'ignore_errors' => true]]);
    @file_get_contents($url, false, $contexte);
    $entetes = http_get_last_response_headers() ?? [];
    $code = isset($entetes[0]) && preg_match('#^HTTP/\S+ (\d{3})#', $entetes[0], $m) ? (int)$m[1] : 0;
    return $code > 0 && $code < 500 ? 1 : 0;
}

function memoire(): array
{
    $lignes = [];
    foreach (file('/proc/meminfo') ?: [] as $l) {
        if (preg_match('/^(\w+):\s+(\d+)/', $l, $m)) {
            $lignes[$m[1]] = (int)$m[2] * 1024;
        }
    }
    if (!isset($lignes['MemTotal'], $lignes['MemAvailable'])) {
        return [];
    }
    return ['mem_utilisee' => $lignes['MemTotal'] - $lignes['MemAvailable']];
}

function echantillon(): array
{
    $charge = @file_get_contents('/proc/loadavg');
    return array_filter(array_merge([
        'lat_gullify' => latence('gullify.app', 443),
        'lat_internet' => latence('1.1.1.1', 443),
        'dispo_gullify' => disponible('https://gullify.app/'),
        'charge' => $charge ? (float)explode(' ', $charge)[0] : null,
    ], memoire()), fn($x) => $x !== null);
}

if (($argv[1] ?? '') === 'historique') {
    $periode = $argv[2] ?? '';
    if (!in_array($periode, PERIODES, true)) {
        fwrite(STDERR, "Période inconnue (6h, 24h, 7j, 30j, 1an).\n");
        exit(2);
    }
    $mesures = new MesuresMaisons();
    $noms = AppConfig::getDB()->query(
        'SELECT maison FROM mesures_brutes UNION SELECT maison FROM mesures_heures UNION SELECT maison FROM mesures_jours'
    )->fetchAll(PDO::FETCH_COLUMN);
    $maisons = [];
    foreach ($noms as $nom) {
        $maisons[$nom] = $mesures->historique($nom, $periode);
    }
    echo json_encode(['periode' => $periode, 'maisons' => $maisons], JSON_UNESCAPED_UNICODE), "\n";
    exit(0);
}

$mesures = new MesuresMaisons();
$mesures->recevoir(NOM_ATELIER, [['t' => time(), 'v' => echantillon()]]);

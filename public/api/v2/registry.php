<?php
/**
 * Le service d'inscription des serveurs — l'API que l'installateur utilise.
 *
 * Sans authentification : celui qui installe n'a pas encore de compte, c'est
 * justement ce qu'il vient chercher. Les garde-fous sont ailleurs — un courriel
 * à confirmer, une limite par adresse IP, des noms réservés.
 *
 *   GET  ?action=disponible&nom=papa
 *   POST ?action=reserver        {nom, courriel}
 *   GET  ?action=etat&reservation=…
 *   POST ?action=ip              {jeton}
 *   GET  ?action=joignable&nom=papa
 *   POST ?action=incident        {genre, detail?, nom?}
 *
 * Répond 404 partout où le service n'est pas configuré : le même code tourne
 * sur les serveurs installés chez les gens, qui n'ont rien à distribuer.
 */
require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Registry.php';

if (!Registry::actif()) {
    v2_fail('registry_absent', 'Ce serveur ne distribue pas de sous-domaines.', 404);
}

/**
 * L'adresse de celui qui appelle, vue depuis l'extérieur.
 *
 * Deux relais se succèdent devant PHP (le Caddy de l'hôte, puis celui du
 * conteneur) : REMOTE_ADDR ne vaut rien ici, c'est la PREMIÈRE adresse de
 * X-Forwarded-For qui est celle du demandeur. On ne la croit que si elle a la
 * forme d'une IPv4 publique — c'est elle qu'on va écrire dans le DNS.
 */
function demandeur(): ?string
{
    $candidats = explode(',', (string)($_SERVER['HTTP_X_FORWARDED_FOR'] ?? ''));
    $candidats[] = $_SERVER['REMOTE_ADDR'] ?? '';

    foreach ($candidats as $morceau) {
        $ip = trim($morceau);
        if (filter_var(
            $ip,
            FILTER_VALIDATE_IP,
            FILTER_FLAG_IPV4 | FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE
        )) {
            return $ip;
        }
    }

    // Rien de public : on ne devine pas. Publier l'adresse d'un relais ou d'un
    // réseau local ferait pointer le nom n'importe où.
    return null;
}

/** L'adresse du demandeur, ou un refus net si on n'en voit pas de publique. */
function demandeurOuRefus(): string
{
    $ip = demandeur();
    if ($ip === null) {
        v2_fail(
            'adresse_invisible',
            'Je ne vois pas d\'adresse publique derrière cette connexion. '
            . 'Si tu passes par un VPN ou un mandataire, coupe-le le temps de l\'installation.',
            400
        );
    }
    return $ip;
}

$action = $_GET['action'] ?? '';
$corps = v2_body();
$ip = demandeur();

try {
    $registre = new Registry();

    switch ($action) {
        // ── Le nom est-il libre ? ─────────────────────────────────────────
        case 'disponible': {
            $nom = (string)($_GET['nom'] ?? '');
            $refus = $registre->refusDuNom($nom);
            v2_ok([
                'nom'        => strtolower(trim($nom)),
                'libre'      => $refus === null,
                'motif'      => $refus,
                'adresse'    => strtolower(trim($nom)) . '.' . $registre->domaine(),
            ]);
        }

        // ── Réserver, puis confirmer par courriel ─────────────────────────
        case 'reserver': {
            if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
                v2_fail('methode', 'POST attendu.', 405);
            }
            $reservation = $registre->reserver(
                (string)($corps['nom'] ?? ''),
                (string)($corps['courriel'] ?? ''),
                demandeurOuRefus()
            );
            v2_ok([
                'reservation' => $reservation,
                'message'     => 'Un courriel vient de partir. Ouvre le lien qu\'il contient.',
            ]);
        }

        case 'etat': {
            v2_ok($registre->etatReservation((string)($_GET['reservation'] ?? '')));
        }

        // ── Le DNS dynamique ──────────────────────────────────────────────
        case 'ip': {
            if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
                v2_fail('methode', 'POST attendu.', 405);
            }
            // L'adresse n'est pas déclarée par l'appelant : c'est celle d'où
            // l'appel arrive. Un serveur ne peut donc pas en publier une autre.
            v2_ok($registre->majIp((string)($corps['jeton'] ?? ''), demandeurOuRefus()));
        }

        // ── Le routeur est-il ouvert ? ────────────────────────────────────
        case 'joignable': {
            $nom = strtolower(trim((string)($_GET['nom'] ?? '')));
            if (!preg_match('/^[a-z0-9-]{1,63}$/', $nom)) {
                v2_fail('nom', 'Nom invalide.', 400);
            }
            v2_ok(joignable($nom . '.' . $registre->domaine()));
        }

        // ── Ce qui a échoué, pour le savoir ───────────────────────────────
        case 'incident': {
            if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
                v2_fail('methode', 'POST attendu.', 405);
            }
            $registre->noter(
                (string)($corps['genre'] ?? 'inconnu'),
                isset($corps['nom']) ? (string)$corps['nom'] : null,
                isset($corps['detail']) ? (string)$corps['detail'] : null,
                // Un incident se note même sans adresse publique visible —
                // c'est souvent le symptôme lui-même.
                $ip ?? ''
            );
            v2_ok(['note' => true]);
        }

        default:
            v2_fail('action', 'Action inconnue : ' . $action, 400);
    }
} catch (RuntimeException $e) {
    // Les messages de Registry sont écrits pour être lus par l'utilisateur :
    // on les transmet tels quels.
    v2_fail('refus', $e->getMessage(), 400);
} catch (Throwable $e) {
    error_log('registry.php : ' . $e->getMessage());
    v2_fail('panne', 'Le service d\'inscription a eu un ennui. Réessaie dans un moment.', 500);
}

/**
 * Essaie d'atteindre le serveur depuis l'extérieur, comme le ferait un
 * téléphone en 5G. C'est la seule façon honnête de dire « ton routeur est
 * ouvert » : le serveur de salon, lui, ne peut pas le savoir tout seul.
 *
 * @return array{joignable: bool, ports: array<string, bool>, ip: ?string}
 */
function joignable(string $fqdn): array
{
    $ip = gethostbyname($fqdn);
    if ($ip === $fqdn) {
        return ['joignable' => false, 'ports' => [], 'ip' => null, 'motif' => 'Le nom ne pointe nulle part.'];
    }

    $ports = [];
    foreach ([80, 443] as $port) {
        $t = @fsockopen($ip, $port, $errno, $errstr, 4);
        $ports[(string)$port] = $t !== false;
        if ($t !== false) {
            fclose($t);
        }
    }

    return [
        'joignable' => $ports['80'] || $ports['443'],
        'ports'     => $ports,
        'ip'        => $ip,
    ];
}

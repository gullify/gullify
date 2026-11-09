<?php
/**
 * La file des transcriptions de recettes (src/TableRecettes.php), côté atelier. Le service
 * gullieats-transcriptions (~/cerveau/outils/transcriptions/) l'appelle par `docker exec` :
 *
 *   attendre [secondes]  rend dès qu'une photo attend (code 0), ou à la fin du délai (code 3)
 *   prendre              la plus ancienne en attente → JSON {id, maison, pages: [chemins]} ; rien s'il n'y en a pas
 *   rendre <id>          le résultat (JSON) sur STDIN → faite
 *   echouer <id>         le message sur STDIN → echec
 */
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/TableRecettes.php';

$action = $argv[1] ?? '';
try {
    $table = new TableRecettes();
    switch ($action) {
        case 'attendre':
            // Une requête légère toutes les 2 s : c'est ce qui rend la lecture immédiate sans minuterie.
            $fin = time() + max(5, (int)($argv[2] ?? 300));
            while (time() < $fin) {
                if ($table->transcriptionsEnAttente() > 0) {
                    exit(0);
                }
                sleep(2);
            }
            exit(3);
        case 'prendre':
            $t = $table->prendreTranscription();
            if ($t !== null) {
                echo json_encode($t, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), "\n";
            }
            exit(0);
        case 'rendre':
            $resultat = json_decode((string)stream_get_contents(STDIN), true);
            if (!is_array($resultat)) {
                throw new DomainException('Résultat : JSON attendu sur STDIN.');
            }
            $table->rendreTranscription((int)($argv[2] ?? 0), $resultat);
            exit(0);
        case 'echouer':
            $table->echecTranscription((int)($argv[2] ?? 0), trim((string)stream_get_contents(STDIN)) ?: 'Lecture impossible.');
            exit(0);
        default:
            fwrite(STDERR, "Usage : transcriptions.php attendre [s] | prendre | rendre <id> | echouer <id>\n");
            exit(2);
    }
} catch (Throwable $e) {
    fwrite(STDERR, $e->getMessage() . "\n");
    exit(1);
}

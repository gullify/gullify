<?php
/**
 * Gullify API v2 — Podcasts (idée #112)
 *
 *   GET  ?action=genres                       → [{id,name}]
 *   GET  ?action=search&q=…&limit=25          → [série]
 *   GET  ?action=discover&genre=1310&limit=30 → [série] (palmarès Apple)
 *   GET  ?action=subscriptions                → [série] (abonnements)
 *   GET  ?action=episodes&feed=…&limit=100    → {show, episodes, subscribed}
 *   POST ?action=subscribe   {feedUrl,title,author,image,description,genre,itunesId}
 *   POST ?action=unsubscribe {feedUrl}
 *   POST ?action=progress    {feedUrl,guid,position,duration,completed}
 *
 * Une « série » : {feedUrl,title,author,image,description,genre,itunesId,
 *                  episodeCount,subscribed}.
 *
 * Le son des épisodes n'est PAS relayé par le serveur : un fichier de podcast
 * est public et stable (contrairement aux URL signées de YouTube ou Bandcamp),
 * l'app le lit donc en direct — une écoute de moins à faire transiter par ici.
 */
declare(strict_types=1);

require_once __DIR__ . '/_v2.php';
require_once __DIR__ . '/../../../src/Podcasts.php';

$ctx    = v2_auth();
$user   = (string) $ctx['user']['username'];
$action = $_GET['action'] ?? $_POST['action'] ?? 'subscriptions';
$body   = v2_body();

/** L'adresse d'un flux telle que la donne le client, refusée si douteuse. */
function pod_feed(string $raw): string
{
    $feed = trim($raw);
    if ($feed === '' || !Podcasts::isHttpUrl($feed)) {
        v2_fail('invalid_request', 'Adresse de flux invalide');
    }
    return $feed;
}

/** Marque d'un « abonné » les séries auxquelles [$user] l'est déjà. */
function pod_mark(array $shows, string $user): array
{
    $mine = [];
    foreach (Podcasts::subscriptions($user) as $s) {
        $mine[Podcasts::key((string) $s['feedUrl'])] = true;
    }
    foreach ($shows as &$show) {
        $show['subscribed'] = isset($mine[Podcasts::key((string) $show['feedUrl'])]);
    }
    return $shows;
}

try {
    switch ($action) {
        case 'genres':
            v2_ok(Podcasts::genres());

        case 'search': {
            $q = trim((string) ($_GET['q'] ?? ''));
            $limit = (int) ($_GET['limit'] ?? 25);
            if ($q === '') v2_ok([]);
            v2_ok(pod_mark(Podcasts::search($q, $limit), $user));
        }

        case 'discover': {
            $genre = (int) ($_GET['genre'] ?? 0);
            if (!Podcasts::isGenre($genre)) {
                v2_fail('invalid_request', 'Catégorie inconnue');
            }
            $limit = (int) ($_GET['limit'] ?? 30);
            v2_ok(pod_mark(Podcasts::top($genre, $limit), $user));
        }

        case 'subscriptions':
            v2_ok(Podcasts::subscriptions($user));

        case 'subscribe': {
            $feed = pod_feed((string) ($body['feedUrl'] ?? $_POST['feedUrl'] ?? ''));
            $ok = Podcasts::subscribe($user, [
                'feedUrl'     => $feed,
                'title'       => (string) ($body['title'] ?? ''),
                'author'      => (string) ($body['author'] ?? ''),
                'image'       => (string) ($body['image'] ?? ''),
                'description' => (string) ($body['description'] ?? ''),
                'genre'       => (string) ($body['genre'] ?? ''),
                'itunesId'    => (int) ($body['itunesId'] ?? 0),
            ]);
            if (!$ok) v2_fail('server_error', 'Abonnement impossible', 500);
            v2_ok(['subscribed' => true]);
        }

        case 'unsubscribe': {
            $feed = pod_feed((string) ($body['feedUrl'] ?? $_POST['feedUrl'] ?? ''));
            Podcasts::unsubscribe($user, $feed);
            v2_ok(['subscribed' => false]);
        }

        case 'episodes': {
            $feed = pod_feed((string) ($_GET['feed'] ?? ''));
            $limit = (int) ($_GET['limit'] ?? 100);
            $refresh = ($_GET['refresh'] ?? '') === '1';
            $data = Podcasts::feed($feed, $limit, $refresh);
            if ($data === null) {
                v2_fail('upstream_error', 'Ce flux de podcast ne répond pas', 502);
            }

            // La fiche du flux prime sur celle gardée à l'abonnement (le nom
            // d'une série change, sa pochette aussi), mais l'abonnement
            // complète ce que le flux ne dit pas.
            $show = $data['show'];
            $show['feedUrl'] = $feed;
            $show['subscribed'] = false;
            $show['itunesId'] = 0;
            foreach (Podcasts::subscriptions($user) as $s) {
                if (Podcasts::key((string) $s['feedUrl']) !== Podcasts::key($feed)) continue;
                $show['subscribed'] = true;
                $show['itunesId'] = (int) $s['itunesId'];
                foreach (['title', 'author', 'image', 'description', 'genre'] as $field) {
                    if (($show[$field] ?? '') === '') $show[$field] = $s[$field];
                }
                break;
            }

            $progress = Podcasts::progress($user, $feed);
            $episodes = [];
            foreach ($data['episodes'] as $e) {
                $state = $progress[Podcasts::key((string) $e['guid'])] ?? null;
                $e['position'] = $state['position'] ?? 0;
                $e['completed'] = $state['completed'] ?? false;
                if (($e['duration'] ?? 0) === 0 && ($state['duration'] ?? 0) > 0) {
                    $e['duration'] = $state['duration'];
                }
                $episodes[] = $e;
            }

            v2_ok(['show' => $show, 'episodes' => $episodes]);
        }

        case 'progress': {
            $feed = pod_feed((string) ($body['feedUrl'] ?? ''));
            $guid = trim((string) ($body['guid'] ?? ''));
            if ($guid === '') v2_fail('invalid_request', 'Épisode inconnu');
            Podcasts::saveProgress(
                $user,
                $feed,
                $guid,
                (int) ($body['position'] ?? 0),
                (int) ($body['duration'] ?? 0),
                !empty($body['completed'])
            );
            v2_ok();
        }

        default:
            v2_fail('invalid_request', "Action inconnue : $action", 404);
    }
} catch (Throwable $e) {
    error_log('API v2 podcasts error: ' . $e->getMessage());
    v2_fail('server_error', 'Erreur serveur', 500);
}

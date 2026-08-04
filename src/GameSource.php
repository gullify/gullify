<?php
/**
 * Gullify — D'où les jeux tirent leur musique.
 *
 * Par défaut un jeu pioche dans toute la bibliothèque. On peut le restreindre
 * à un ou plusieurs genres, à une ou plusieurs playlists, ou aux favoris — en
 * solo comme en partie à plusieurs (c'est alors la bibliothèque de l'hôte qui
 * est filtrée, puisque c'est elle qui fournit les manches).
 *
 * Le filtre est rendu sous forme de fragment SQL à coller dans un WHERE, avec
 * ses paramètres. Les alias de tables sont passés en argument : les requêtes
 * des jeux filtrent tantôt la table principale (`s`, `al`, `a`), tantôt une
 * sous-requête qui choisit un titre par album (`s2`, `al2`, `a2`).
 */

class GameSource
{
    /** Les quatre viviers possibles. */
    public const MODES = ['all', 'genres', 'playlists', 'favorites'];

    /** Garde-fou : une sélection démesurée ne veut plus rien dire. */
    private const MAX_ITEMS = 60;

    /** Le vivier par défaut : toute la bibliothèque. */
    public static function all(): array
    {
        return ['mode' => 'all', 'genres' => [], 'playlists' => []];
    }

    /**
     * Nettoie une fiche venue du client (corps JSON, query string) ou de la
     * base (colonne JSON). Toute valeur douteuse retombe sur « tout » : un
     * filtre mal formé ne doit jamais empêcher de jouer.
     */
    public static function normalize(mixed $raw): array
    {
        if (is_string($raw)) $raw = json_decode($raw, true);
        if (!is_array($raw)) return self::all();

        $mode = is_string($raw['mode'] ?? null) ? $raw['mode'] : 'all';
        if (!in_array($mode, self::MODES, true)) return self::all();

        $genres    = self::strings($raw['genres'] ?? []);
        $playlists = self::ids($raw['playlists'] ?? []);

        // Une sélection vide ne filtre rien : mieux vaut tout jouer que de ne
        // rien pouvoir tirer.
        if ($mode === 'genres' && !$genres) return self::all();
        if ($mode === 'playlists' && !$playlists) return self::all();

        return ['mode' => $mode, 'genres' => $genres, 'playlists' => $playlists];
    }

    /**
     * La fiche portée par la requête HTTP, en query string
     * (`?source=genres&genres=Rock,Jazz`) comme en corps JSON
     * (`{"source":{"mode":"genres","genres":["Rock"]}}`).
     */
    public static function fromRequest(array $body = []): array
    {
        $raw = $_GET['source'] ?? $_POST['source'] ?? $body['source'] ?? null;
        if (is_array($raw)) return self::normalize($raw);
        // Fiche entière passée en query string : c'est ce que fait l'app, un
        // nom de genre pouvant contenir une virgule (« Rock, Pop »).
        if (is_string($raw) && str_starts_with(ltrim($raw), '{')) {
            return self::normalize(json_decode($raw, true));
        }

        return self::normalize([
            'mode'      => is_string($raw) ? $raw : 'all',
            'genres'    => $_GET['genres']    ?? $_POST['genres']    ?? $body['genres']    ?? [],
            'playlists' => $_GET['playlists'] ?? $_POST['playlists'] ?? $body['playlists'] ?? [],
        ]);
    }

    /** Vrai quand rien n'est filtré (aucun fragment SQL à ajouter). */
    public static function isAll(array $src): bool
    {
        return ($src['mode'] ?? 'all') === 'all';
    }

    /**
     * Filtre portant sur des titres : rend `[fragment, paramètres]` à coller
     * dans le WHERE d'une requête où `$s` est la table des titres, `$al` son
     * album et `$a` l'artiste de cet album.
     */
    public static function songWhere(
        string $user,
        array $src,
        string $s = 's',
        string $al = 'al',
        string $a = 'a'
    ): array {
        switch ($src['mode'] ?? 'all') {
            case 'genres':
                // Le genre vit sur l'album, mais beaucoup de bibliothèques ne
                // le portent que sur l'artiste : on accepte les deux.
                $in = self::placeholders($src['genres']);
                return [
                    " AND ($al.genre IN ($in) OR $a.genre IN ($in))",
                    array_merge($src['genres'], $src['genres']),
                ];

            case 'playlists':
                $in = self::placeholders($src['playlists']);
                return [
                    " AND EXISTS (SELECT 1 FROM playlist_songs ps
                                    JOIN playlists pl ON pl.id = ps.playlist_id
                                   WHERE ps.song_id = $s.id
                                     AND pl.user = ? AND pl.id IN ($in))",
                    array_merge([$user], $src['playlists']),
                ];

            case 'favorites':
                return [
                    " AND EXISTS (SELECT 1 FROM favorites fav
                                   WHERE fav.song_id = $s.id AND fav.user = ?)",
                    [$user],
                ];

            default:
                return ['', []];
        }
    }

    /**
     * Filtre portant sur des albums : un album entre dans le vivier dès qu'un
     * de ses titres y entre (playlists, favoris) — le genre, lui, se lit
     * directement sur l'album ou son artiste.
     */
    public static function albumWhere(
        string $user,
        array $src,
        string $al = 'al',
        string $a = 'a'
    ): array {
        $mode = $src['mode'] ?? 'all';
        if ($mode === 'all' || $mode === 'genres') {
            return self::songWhere($user, $src, 's', $al, $a);
        }
        // `sa` : alias dédié, pour ne pas heurter la table des titres que la
        // requête appelante manipule peut-être déjà sous le nom `s`.
        [$inner, $params] = self::songWhere($user, $src, 'sa', $al, $a);
        return [
            " AND EXISTS (SELECT 1 FROM songs sa WHERE sa.album_id = $al.id$inner)",
            $params,
        ];
    }

    // ─────────────────────────────────────────────────────────── internes ──

    private static function placeholders(array $values): string
    {
        return implode(',', array_fill(0, count($values), '?'));
    }

    /** Liste de chaînes, en tableau ou en « a,b,c ». */
    private static function strings(mixed $raw): array
    {
        $out = [];
        foreach (self::items($raw) as $v) {
            $v = trim((string)$v);
            if ($v !== '') $out[] = $v;
        }
        return array_slice(array_values(array_unique($out)), 0, self::MAX_ITEMS);
    }

    /** Liste d'identifiants, en tableau ou en « 1,2,3 ». */
    private static function ids(mixed $raw): array
    {
        $out = [];
        foreach (self::items($raw) as $v) {
            $id = (int)$v;
            if ($id > 0) $out[] = $id;
        }
        return array_slice(array_values(array_unique($out)), 0, self::MAX_ITEMS);
    }

    private static function items(mixed $raw): array
    {
        if (is_array($raw)) return $raw;
        if (is_scalar($raw)) return explode(',', (string)$raw);
        return [];
    }
}

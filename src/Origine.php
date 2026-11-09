<?php
/**
 * Gullify — D'où vient un artiste.
 *
 * L'origine n'est PAS un genre : « rock québécois », c'est du Rock venu du
 * Québec. On la range donc à part (colonne `artists.origine`), et c'est
 * l'app qui croise les deux (Rock → [Québec] [France]…).
 *
 * Deux sources, dans cet ordre :
 *   1. les étiquettes Last.fm (« quebec », « french », « belgian »…) — elles
 *      connaissent bien la scène d'ici, et la taxonomie des genres les jetait ;
 *   2. la région ou le pays de MusicBrainz (`area`, `begin-area`, `country`),
 *      fiable quand il est rempli.
 *
 * La liste est courte et fermée, comme celle des genres : un nom de pays
 * inconnu ne crée pas une origine de plus, il ne range rien.
 */

class Origine
{
    public const QUEBEC     = 'Québec';
    public const ACADIE     = 'Acadie';
    public const CANADA     = 'Canada';
    public const FRANCE     = 'France';
    public const BELGIQUE   = 'Belgique';
    public const SUISSE     = 'Suisse';
    public const ETATS_UNIS = 'États-Unis';
    public const ROYAUME_UNI = 'Royaume-Uni';
    public const IRLANDE    = 'Irlande';
    public const AUSTRALIE  = 'Australie';
    public const ALLEMAGNE  = 'Allemagne';
    public const SCANDINAVIE = 'Scandinavie';
    public const ITALIE     = 'Italie';
    public const ESPAGNE    = 'Espagne';
    public const AMERIQUE_LATINE = 'Amérique latine';
    public const AFRIQUE    = 'Afrique';
    public const CARAIBES   = 'Caraïbes';
    public const JAPON      = 'Japon';
    public const COREE      = 'Corée';

    /** L'ordre d'affichage : d'ici d'abord, puis du plus proche au plus loin. */
    public const ALL = [
        self::QUEBEC, self::ACADIE, self::CANADA, self::FRANCE, self::BELGIQUE,
        self::SUISSE, self::ETATS_UNIS, self::ROYAUME_UNI, self::IRLANDE,
        self::AUSTRALIE, self::ALLEMAGNE, self::SCANDINAVIE, self::ITALIE,
        self::ESPAGNE, self::AMERIQUE_LATINE, self::AFRIQUE, self::CARAIBES,
        self::JAPON, self::COREE,
    ];

    /**
     * Étiquettes (normalisées comme GenreTaxonomy::normalize) => origine.
     * Un groupe étiqueté « canadian » ET « quebec » est québécois (voir
     * depuisTags).
     */
    private const TAGS = [
        'quebec' => self::QUEBEC, 'quebecois' => self::QUEBEC,
        'quebecoise' => self::QUEBEC, 'quebecer' => self::QUEBEC,
        'keb' => self::QUEBEC, 'musique quebecoise' => self::QUEBEC,
        'chanson quebecoise' => self::QUEBEC, 'rock quebecois' => self::QUEBEC,
        'rap quebecois' => self::QUEBEC, 'rap keb' => self::QUEBEC,
        'pop quebecoise' => self::QUEBEC, 'trad quebecois' => self::QUEBEC,
        'folk quebecois' => self::QUEBEC, 'metal quebecois' => self::QUEBEC,
        'punk quebecois' => self::QUEBEC, 'hip hop quebecois' => self::QUEBEC,
        'traditionnel quebecois' => self::QUEBEC, 'montreal' => self::QUEBEC,
        'quebec city' => self::QUEBEC, 'ville de quebec' => self::QUEBEC,
        'quebec province' => self::QUEBEC,
        'acadien' => self::ACADIE, 'acadienne' => self::ACADIE,
        'acadian' => self::ACADIE, 'acadie' => self::ACADIE, 'chiac' => self::ACADIE,
        'canadian' => self::CANADA, 'canada' => self::CANADA,
        'canadien' => self::CANADA, 'canadienne' => self::CANADA,
        'ontario' => self::CANADA, 'toronto' => self::CANADA,
        'vancouver' => self::CANADA, 'canadian rock' => self::CANADA,
        'canadian indie' => self::CANADA, 'canadian hip hop' => self::CANADA,
        'french' => self::FRANCE, 'france' => self::FRANCE,
        'chanson francaise' => self::FRANCE, 'rap francais' => self::FRANCE,
        'french rap' => self::FRANCE, 'french pop' => self::FRANCE,
        'french rock' => self::FRANCE, 'rock francais' => self::FRANCE,
        'pop francaise' => self::FRANCE, 'french hip hop' => self::FRANCE,
        'nouvelle chanson francaise' => self::FRANCE, 'paris' => self::FRANCE,
        'french touch' => self::FRANCE, 'variete francaise' => self::FRANCE,
        'belgian' => self::BELGIQUE, 'belgique' => self::BELGIQUE,
        'belgium' => self::BELGIQUE, 'belge' => self::BELGIQUE,
        'swiss' => self::SUISSE, 'suisse' => self::SUISSE, 'switzerland' => self::SUISSE,
        'american' => self::ETATS_UNIS, 'usa' => self::ETATS_UNIS,
        'americain' => self::ETATS_UNIS,
        'british' => self::ROYAUME_UNI, 'uk' => self::ROYAUME_UNI,
        'english' => self::ROYAUME_UNI, 'england' => self::ROYAUME_UNI,
        'scottish' => self::ROYAUME_UNI, 'welsh' => self::ROYAUME_UNI,
        'britpop' => self::ROYAUME_UNI, 'brit pop' => self::ROYAUME_UNI,
        'irish' => self::IRLANDE, 'ireland' => self::IRLANDE,
        'australian' => self::AUSTRALIE, 'australia' => self::AUSTRALIE,
        'german' => self::ALLEMAGNE, 'deutsch' => self::ALLEMAGNE,
        'germany' => self::ALLEMAGNE, 'deutschrock' => self::ALLEMAGNE,
        'swedish' => self::SCANDINAVIE, 'norwegian' => self::SCANDINAVIE,
        'danish' => self::SCANDINAVIE, 'finnish' => self::SCANDINAVIE,
        'icelandic' => self::SCANDINAVIE, 'scandinavian' => self::SCANDINAVIE,
        'italian' => self::ITALIE, 'italiano' => self::ITALIE, 'italia' => self::ITALIE,
        'spanish' => self::ESPAGNE, 'espanol' => self::ESPAGNE, 'spain' => self::ESPAGNE,
        'latin' => self::AMERIQUE_LATINE, 'latino' => self::AMERIQUE_LATINE,
        'mexican' => self::AMERIQUE_LATINE, 'brazilian' => self::AMERIQUE_LATINE,
        'argentina' => self::AMERIQUE_LATINE, 'colombian' => self::AMERIQUE_LATINE,
        'cuban' => self::CARAIBES, 'jamaican' => self::CARAIBES,
        'haitian' => self::CARAIBES, 'haiti' => self::CARAIBES,
        'african' => self::AFRIQUE, 'afrique' => self::AFRIQUE,
        'malian' => self::AFRIQUE, 'senegalese' => self::AFRIQUE,
        'nigerian' => self::AFRIQUE, 'congolese' => self::AFRIQUE,
        'japanese' => self::JAPON, 'j pop' => self::JAPON, 'j rock' => self::JAPON,
        'korean' => self::COREE, 'k pop' => self::COREE, 'kpop' => self::COREE,
    ];

    /**
     * Pays ISO 3166-1 (champ `country` de MusicBrainz) => origine.
     */
    private const PAYS = [
        'CA' => self::CANADA, 'FR' => self::FRANCE, 'BE' => self::BELGIQUE,
        'CH' => self::SUISSE, 'US' => self::ETATS_UNIS, 'GB' => self::ROYAUME_UNI,
        'IE' => self::IRLANDE, 'AU' => self::AUSTRALIE, 'NZ' => self::AUSTRALIE,
        'DE' => self::ALLEMAGNE, 'AT' => self::ALLEMAGNE,
        'SE' => self::SCANDINAVIE, 'NO' => self::SCANDINAVIE, 'DK' => self::SCANDINAVIE,
        'FI' => self::SCANDINAVIE, 'IS' => self::SCANDINAVIE,
        'IT' => self::ITALIE, 'ES' => self::ESPAGNE,
        'MX' => self::AMERIQUE_LATINE, 'BR' => self::AMERIQUE_LATINE,
        'AR' => self::AMERIQUE_LATINE, 'CO' => self::AMERIQUE_LATINE,
        'CL' => self::AMERIQUE_LATINE, 'PE' => self::AMERIQUE_LATINE,
        'VE' => self::AMERIQUE_LATINE, 'UY' => self::AMERIQUE_LATINE,
        'CU' => self::CARAIBES, 'JM' => self::CARAIBES, 'HT' => self::CARAIBES,
        'DO' => self::CARAIBES, 'PR' => self::CARAIBES, 'TT' => self::CARAIBES,
        'ML' => self::AFRIQUE, 'SN' => self::AFRIQUE, 'NG' => self::AFRIQUE,
        'CD' => self::AFRIQUE, 'CG' => self::AFRIQUE, 'CI' => self::AFRIQUE,
        'CM' => self::AFRIQUE, 'GH' => self::AFRIQUE, 'ZA' => self::AFRIQUE,
        'DZ' => self::AFRIQUE, 'MA' => self::AFRIQUE, 'TN' => self::AFRIQUE,
        'ET' => self::AFRIQUE, 'KE' => self::AFRIQUE, 'BF' => self::AFRIQUE,
        'GN' => self::AFRIQUE, 'BJ' => self::AFRIQUE, 'MG' => self::AFRIQUE,
        'JP' => self::JAPON, 'KR' => self::COREE,
    ];

    /**
     * Les régions MusicBrainz qui disent « Québec » : la province elle-même
     * et ses villes (une `area` est souvent la ville natale, pas la province).
     */
    private const LIEUX_QUEBEC = [
        'quebec', 'montreal', 'laval', 'gatineau', 'longueuil', 'sherbrooke',
        'saguenay', 'chicoutimi', 'jonquiere', 'levis', 'trois rivieres',
        'terrebonne', 'saint jean sur richelieu', 'repentigny', 'brossard',
        'drummondville', 'saint jerome', 'granby', 'blainville', 'saint hyacinthe',
        'shawinigan', 'dollard des ormeaux', 'rimouski', 'victoriaville',
        'mirabel', 'joliette', 'sorel tracy', 'val d or', 'rouyn noranda',
        'sept iles', 'baie comeau', 'alma', 'magog', 'matane', 'gaspe',
        'rivieres du loup', 'riviere du loup', 'thetford mines', 'roberval',
        'amos', 'la malbaie', 'iles de la madeleine', 'beloeil', 'boucherville',
        'chateauguay', 'vaudreuil dorion', 'sainte therese', 'outremont',
        'verdun', 'lachine', 'westmount', 'la tuque', 'dolbeau mistassini',
        'saint georges', 'charlesbourg', 'beauport', 'sainte foy', 'nicolet',
        'louiseville', 'montmagny', 'kamouraska', 'carleton sur mer',
    ];

    /** Lieux acadiens (Nouveau-Brunswick francophone surtout). */
    private const LIEUX_ACADIE = [
        'moncton', 'dieppe', 'caraquet', 'shippagan', 'edmundston', 'bouctouche',
        'tracadie', 'tracadie sheila', 'acadie', 'acadia', 'cheticamp',
    ];

    /**
     * L'origine que disent des étiquettes pesées (Last.fm), ou null.
     *
     * @param array<array{name: string, count: int}> $tags
     */
    public static function depuisTags(array $tags): ?string
    {
        $poids = [];
        $top   = 1;
        foreach ($tags as $t) $top = max($top, (int)($t['count'] ?? 0));

        foreach ($tags as $t) {
            $o = self::TAGS[self::normaliser((string)($t['name'] ?? ''))] ?? null;
            if ($o === null) continue;
            $p = max(0, (int)($t['count'] ?? 0)) / $top;
            // Une étiquette tout en bas d'une longue liste (moins de 5 %) est
            // un vote isolé : elle ne range pas un artiste.
            if ($p < 0.05 && count($tags) > 3) continue;
            $poids[$o] = max($poids[$o] ?? 0, $p);
        }
        if (!$poids) return null;

        // Une région canadienne efface le Canada : elle le précise, elle ne
        // le contredit pas. Entre les autres, le plus voté l'emporte.
        if (isset($poids[self::CANADA]) && (isset($poids[self::QUEBEC]) || isset($poids[self::ACADIE]))) {
            unset($poids[self::CANADA]);
        }
        arsort($poids);

        return array_key_first($poids);
    }

    /**
     * L'origine que dit une fiche d'artiste MusicBrainz (recherche ou
     * détail) : la ville ou la région d'abord, le pays à défaut.
     */
    public static function depuisMusicBrainz(array $artiste): ?string
    {
        foreach (['begin-area', 'area'] as $champ) {
            $lieu = self::normaliser((string)($artiste[$champ]['name'] ?? ''));
            if ($lieu === '') continue;
            if (in_array($lieu, self::LIEUX_QUEBEC, true)) return self::QUEBEC;
            if (in_array($lieu, self::LIEUX_ACADIE, true)) return self::ACADIE;
            foreach ((array)($artiste[$champ]['iso-3166-2-codes'] ?? []) as $code) {
                if ($code === 'CA-QC') return self::QUEBEC;
            }
        }

        $pays = strtoupper((string)($artiste['country'] ?? ''));
        if ($pays === '') {
            foreach (['area', 'begin-area'] as $champ) {
                foreach ((array)($artiste[$champ]['iso-3166-1-codes'] ?? []) as $code) {
                    $pays = strtoupper((string)$code);
                    break 2;
                }
            }
        }

        return self::PAYS[$pays] ?? null;
    }

    /** Une origine de la liste, à la casse et aux accents près ; sinon null. */
    public static function canonique(string $brut): ?string
    {
        $n = self::normaliser($brut);
        if ($n === '') return null;
        foreach (self::ALL as $o) {
            if (self::normaliser($o) === $n) return $o;
        }
        return null;
    }

    private static function normaliser(string $s): string
    {
        require_once __DIR__ . '/GenreTaxonomy.php';
        return GenreTaxonomy::normalize($s);
    }
}

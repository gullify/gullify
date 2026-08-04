<?php
/**
 * Gullify — La taxonomie de genres, volontairement courte et fermée.
 *
 * Une bibliothèque se range mal quand chaque fichier apporte son étiquette :
 * « Melodic Death Metal », « Music », « Special Purpose Artist », « Français »…
 * On ramène donc TOUT à une liste de genres principaux — pas de sous-genres,
 * pas de dix nuances de métal — et c'est cette liste, et elle seule, qui sert
 * de rangement (parcours par genre, filtre des jeux, choix manuel).
 *
 * Le classement se fait en trois temps, sur une forme normalisée de
 * l'étiquette (minuscules, sans accent ni ponctuation) :
 *
 *   1. les étiquettes sans aucun signal musical (« Music », « Various »,
 *      « Canadian », « 90s »…) sont écartées — mieux vaut aucun genre qu'un
 *      faux genre, et l'étiquette suivante aura peut-être mieux à dire ;
 *   2. une correspondance exacte (les alias connus) ;
 *   3. une correspondance par mots, dans un ORDRE QUI COMPTE : le plus précis
 *      d'abord. « melodic death metal » doit tomber sur Métal avant que
 *      « folk rock » ne tombe sur Rock, et « chanson québécoise » ne doit pas
 *      être avalé par un mot plus générique.
 *
 * Chaque règle porte un rang, qui sert à départager plusieurs étiquettes
 * (voir pickFromTags) :
 *   - RANK_STRONG : les genres d'ici (chanson, trad, acadien). Un artiste
 *     étiqueté « néo-trad » l'est rarement par hasard ;
 *   - RANK_NORMAL : les genres musicaux ordinaires ;
 *   - RANK_WEAK : les indices de langue ou de pays (« français »), qui ne
 *     servent qu'à défaut de mieux.
 */

class GenreTaxonomy
{
    // ── Les 21 genres, tels qu'ils s'affichent ───────────────────────────────
    public const CHANSON   = 'Chanson québécoise/francophone';
    public const TRAD      = 'Traditionnel québécois';
    public const ACADIEN   = 'Acadien';
    public const FOLK      = 'Folk';
    public const COUNTRY   = 'Country';
    public const POP       = 'Pop';
    public const ROCK      = 'Rock';
    public const ALTERNATIF = 'Alternatif / Indie';
    public const PUNK      = 'Punk';
    public const METAL     = 'Métal';
    public const HIPHOP    = 'Hip-hop / Rap';
    public const RNB       = 'R&B / Soul';
    public const REGGAE    = 'Reggae';
    public const JAZZ      = 'Jazz';
    public const BLUES     = 'Blues';
    public const ELECTRO   = 'Électronique';
    public const CLASSIQUE = 'Classique';
    public const MONDE     = 'Musique du monde';
    public const GOSPEL    = 'Gospel / Spirituel';
    public const TRAMES    = 'Trames sonores';
    public const ENFANTS   = 'Musique pour enfants';

    /** La liste complète, dans l'ordre d'affichage voulu. */
    public const ALL = [
        self::CHANSON, self::TRAD, self::ACADIEN, self::FOLK, self::COUNTRY,
        self::POP, self::ROCK, self::ALTERNATIF, self::PUNK, self::METAL,
        self::HIPHOP, self::RNB, self::REGGAE, self::JAZZ, self::BLUES,
        self::ELECTRO, self::CLASSIQUE, self::MONDE, self::GOSPEL,
        self::TRAMES, self::ENFANTS,
    ];

    public const RANK_WEAK   = 1;
    public const RANK_NORMAL = 2;
    public const RANK_STRONG = 3;

    /**
     * Étiquettes sans aucun signal musical. Ce ne sont pas des genres : ce
     * sont des restes de tags (ID3 « Music », decennies, nationalités), ou
     * des catégories que la liste ne couvre pas (humour, parlé, Noël). On
     * passe à l'étiquette suivante plutôt que de ranger de travers.
     */
    private const NOISE = [
        'music', 'musique', 'audio', 'sound', 'song', 'songs', 'single',
        'album', 'albums', 'compilation', 'best of', 'greatest hits',
        'other', 'others', 'autre', 'autres', 'divers', 'miscellaneous',
        'misc', 'general', 'unknown', 'inconnu', 'undefined', 'none', 'n a',
        'various', 'various artists', 'artiste divers', 'special purpose artist',
        'seen live', 'favorites', 'favourites', 'cover', 'covers', 'tribute',
        'male vocalists', 'female vocalists', 'vocal', 'vocals', 'instrumental',
        'instrumentale', 'acapella', 'a cappella', 'live', 'demo', 'remix',
        'oldies', 'retro', 'nostalgie', 'classic', 'classics', 'modern',
        'contemporary', 'popular', 'mainstream', 'underground', 'experimental music',
        '60s', '70s', '80s', '90s', '2000s', '2010s', '2020s',
        '1960s', '1970s', '1980s', '1990s', '20th century', '21st century',
        'canadian', 'canadien', 'american', 'americain', 'british', 'english',
        'anglais', 'usa', 'uk', 'canada', 'quebec province', 'ontario',
        'western europe', 'eastern europe', 'northern europe', 'southern europe',
        'north america', 'northern america',
        'comedy', 'comedie', 'humour', 'humor', 'humoristique', 'parody',
        'parodie', 'novelty', 'stand up', 'spoken word', 'parle', 'conte',
        'contes', 'audiobook', 'livre audio', 'podcast',
        'holiday', 'christmas', 'noel', 'temps des fetes',
        // Ce que les catalogues rangent avec la musique sans en être (Deezer).
        'livre audio', 'livres audio', 'histoires', 'musique allemande',
    ];

    /**
     * Alias reconnus tels quels (correspondance exacte sur la forme
     * normalisée). Les noms canoniques y figurent aussi : reclasser une
     * bibliothèque déjà classée ne doit rien changer.
     *
     * Format : genre canonique => [étiquettes, …]
     */
    private const EXACT = [
        self::CHANSON => [
            'chanson quebecoise/francophone', 'chanson', 'chansons',
            'chanson francaise', 'chanson quebecoise', 'chanson francophone',
            'nouvelle chanson francaise', 'variete', 'variete francaise',
            'variete internationale', 'auteur compositeur interprete',
            'auteur interprete', 'chansonnier', 'musique francophone',
            'yeye', 'ye ye',
        ],
        self::TRAD => [
            'traditionnel quebecois', 'trad', 'neo trad', 'neotrad',
            'traditionnel', 'traditionnelle', 'musique traditionnelle',
            'trad quebecois', 'folk quebecois', 'folklore', 'folklorique',
            'turlutte', 'chanson traditionnelle', 'musique du terroir',
        ],
        self::ACADIEN => [
            'acadien', 'acadienne', 'acadian', 'acadie', 'chiac',
            'musique acadienne',
        ],
        self::ALTERNATIF => ['alternatif / indie', 'alternatif', 'alt'],
        self::HIPHOP     => ['hip-hop / rap', 'hip hop rap', 'rap quebecois', 'rap keb'],
        self::RNB        => ['r and b / soul', 'r and b', 'r b', 'rnb', 'rhythm and blues'],
        self::METAL      => ['metal', 'metal and hard rock', 'metal hard rock'],
        self::ELECTRO    => ['electronique', 'electronic', 'electro', 'electronica'],
        self::CLASSIQUE  => ['classique', 'classical', 'musique classique'],
        self::MONDE      => [
            'musique du monde', 'world', 'world music', 'monde',
            // Les rayons « musique de » des catalogues (Deezer).
            'musique asiatique', 'musique bresilienne', 'musique indienne',
            'musique arabe', 'musique latine',
        ],
        self::GOSPEL     => ['gospel / spirituel', 'gospel', 'spirituel'],
        self::TRAMES     => [
            'trames sonores', 'trame sonore', 'soundtrack', 'soundtracks',
            'bande originale', 'bande son', 'ost', 'original score', 'score',
            'films jeux video', 'jeux video',
        ],
        self::ENFANTS    => [
            'musique pour enfants', 'enfants', 'enfant', 'jeunesse',
            'children', 'childrens music', 'kids', 'comptine', 'comptines',
            'berceuse', 'berceuses', 'lullaby', 'lullabies', 'nursery rhymes',
            'disney', 'comptines chansons',
        ],
        self::PUNK  => ['punk', 'punk rock', 'ska', 'hardcore'],
        self::ROCK  => ['rock', 'rock/pop', 'rock pop'],
        self::POP   => ['pop', 'pop/rock'],
        self::FOLK  => ['folk', 'acoustique', 'acoustic'],
        self::JAZZ  => ['jazz'],
        self::BLUES => ['blues'],
        self::COUNTRY => ['country', 'country and folk'],
        self::REGGAE  => ['reggae'],
    ];

    /**
     * Règles par mots, DU PLUS PRÉCIS AU PLUS GÉNÉRAL — l'ordre fait le
     * classement. La correspondance se fait sur des mots entiers : « emo » ne
     * déclenche pas sur « emotional », et « punk » ne déclenche pas sur
     * « noquarterpunk ».
     *
     * Format : [expression, genre, rang]
     */
    private const RULES = [
        // ── Composés à traiter avant le mot large qu'ils contiennent ────────
        // « French pop » est l'étiquette que les catalogues collent à la
        // chanson d'ici : elle dit la langue avant de dire la pop.
        ['french pop',       self::CHANSON,    self::RANK_NORMAL],
        ['pop francaise',    self::CHANSON,    self::RANK_NORMAL],
        ['post punk',        self::ALTERNATIF, self::RANK_NORMAL],
        ['pop rock',         self::POP,        self::RANK_NORMAL],
        ['country rock',     self::COUNTRY,    self::RANK_NORMAL],
        ['country pop',      self::COUNTRY,    self::RANK_NORMAL],
        ['blues rock',       self::BLUES,      self::RANK_NORMAL],

        // ── Métal (avant punk : « metalcore » n'est pas du punk) ────────────
        ['metalcore', self::METAL, self::RANK_NORMAL],
        ['deathcore', self::METAL, self::RANK_NORMAL],
        ['grindcore', self::METAL, self::RANK_NORMAL],
        ['djent',     self::METAL, self::RANK_NORMAL],
        ['thrash',    self::METAL, self::RANK_NORMAL],
        ['sludge',    self::METAL, self::RANK_NORMAL],
        ['metal',     self::METAL, self::RANK_NORMAL],

        // ── Punk (le ska d'ici est un ska-punk) ─────────────────────────────
        ['post hardcore',    self::PUNK, self::RANK_NORMAL],
        ['melodic hardcore', self::PUNK, self::RANK_NORMAL],
        ['hardcore punk',    self::PUNK, self::RANK_NORMAL],
        ['skate punk',       self::PUNK, self::RANK_NORMAL],
        ['ska punk',         self::PUNK, self::RANK_NORMAL],
        ['ska core',         self::PUNK, self::RANK_NORMAL],
        ['skacore',          self::PUNK, self::RANK_NORMAL],
        ['pop punk',         self::PUNK, self::RANK_NORMAL],
        ['celtic punk',      self::PUNK, self::RANK_NORMAL],
        ['folk punk',        self::PUNK, self::RANK_NORMAL],
        ['horror punk',      self::PUNK, self::RANK_NORMAL],
        ['street punk',      self::PUNK, self::RANK_NORMAL],
        ['crust',            self::PUNK, self::RANK_NORMAL],
        ['emocore',          self::PUNK, self::RANK_NORMAL],
        ['screamo',          self::PUNK, self::RANK_NORMAL],
        ['emo',              self::PUNK, self::RANK_NORMAL],
        ['punk',             self::PUNK, self::RANK_NORMAL],
        ['hardcore',         self::PUNK, self::RANK_NORMAL],
        ['two tone',         self::PUNK, self::RANK_NORMAL],
        ['2 tone',           self::PUNK, self::RANK_NORMAL],
        ['ska',              self::PUNK, self::RANK_NORMAL],

        // ── Hip-hop ─────────────────────────────────────────────────────────
        ['hip hop',      self::HIPHOP, self::RANK_NORMAL],
        ['hiphop',       self::HIPHOP, self::RANK_NORMAL],
        ['rap',          self::HIPHOP, self::RANK_NORMAL],
        ['trap',         self::HIPHOP, self::RANK_NORMAL],
        ['boom bap',     self::HIPHOP, self::RANK_NORMAL],
        ['grime',        self::HIPHOP, self::RANK_NORMAL],
        ['turntablism',  self::HIPHOP, self::RANK_NORMAL],

        // ── R&B / Soul (avant blues : « rhythm and blues ») ─────────────────
        ['neo soul',       self::RNB, self::RANK_NORMAL],
        ['soul',           self::RNB, self::RANK_NORMAL],
        ['funk',           self::RNB, self::RANK_NORMAL],
        ['motown',         self::RNB, self::RANK_NORMAL],
        ['disco',          self::RNB, self::RANK_NORMAL],
        ['doo wop',        self::RNB, self::RANK_NORMAL],
        ['new jack swing', self::RNB, self::RANK_NORMAL],

        // ── Gospel (après métal/punk : le « christian metal » reste du métal) ─
        ['gospel',    self::GOSPEL, self::RANK_NORMAL],
        ['worship',   self::GOSPEL, self::RANK_NORMAL],
        ['praise',    self::GOSPEL, self::RANK_NORMAL],
        ['christian', self::GOSPEL, self::RANK_NORMAL],
        ['chretien',  self::GOSPEL, self::RANK_NORMAL],
        ['chretienne', self::GOSPEL, self::RANK_NORMAL],
        ['ccm',       self::GOSPEL, self::RANK_NORMAL],
        ['spiritual', self::GOSPEL, self::RANK_NORMAL],
        ['spirituals', self::GOSPEL, self::RANK_NORMAL],
        ['liturgique', self::GOSPEL, self::RANK_NORMAL],
        ['sacred',    self::GOSPEL, self::RANK_NORMAL],

        // ── Reggae ──────────────────────────────────────────────────────────
        ['reggae',     self::REGGAE, self::RANK_NORMAL],
        ['dancehall',  self::REGGAE, self::RANK_NORMAL],
        ['rocksteady', self::REGGAE, self::RANK_NORMAL],
        ['ragga',      self::REGGAE, self::RANK_NORMAL],
        ['dub',        self::REGGAE, self::RANK_NORMAL],

        // ── Jazz ────────────────────────────────────────────────────────────
        ['jazz',      self::JAZZ, self::RANK_NORMAL],
        ['bebop',     self::JAZZ, self::RANK_NORMAL],
        ['be bop',    self::JAZZ, self::RANK_NORMAL],
        ['hard bop',  self::JAZZ, self::RANK_NORMAL],
        ['post bop',  self::JAZZ, self::RANK_NORMAL],
        ['big band',  self::JAZZ, self::RANK_NORMAL],
        ['dixieland', self::JAZZ, self::RANK_NORMAL],
        ['ragtime',   self::JAZZ, self::RANK_NORMAL],
        ['swing',     self::JAZZ, self::RANK_NORMAL],

        // ── Blues ───────────────────────────────────────────────────────────
        ['blues',         self::BLUES, self::RANK_NORMAL],
        ['boogie woogie', self::BLUES, self::RANK_NORMAL],

        // ── Country ─────────────────────────────────────────────────────────
        ['country',      self::COUNTRY, self::RANK_NORMAL],
        ['bluegrass',    self::COUNTRY, self::RANK_NORMAL],
        ['americana',    self::COUNTRY, self::RANK_NORMAL],
        ['honky tonk',   self::COUNTRY, self::RANK_NORMAL],
        ['western swing', self::COUNTRY, self::RANK_NORMAL],

        // ── Folk (avant rock : « folk rock » penche du côté folk) ───────────
        ['folk',              self::FOLK, self::RANK_NORMAL],
        ['singer songwriter', self::FOLK, self::RANK_NORMAL],
        ['celtic',            self::FOLK, self::RANK_NORMAL],
        ['celtique',          self::FOLK, self::RANK_NORMAL],
        ['acoustic',          self::FOLK, self::RANK_NORMAL],
        ['acoustique',        self::FOLK, self::RANK_NORMAL],

        // ── Alternatif / Indie (avant rock : « indie rock », « art rock ») ──
        ['alternative', self::ALTERNATIF, self::RANK_NORMAL],
        ['alternatif',  self::ALTERNATIF, self::RANK_NORMAL],
        ['indie',       self::ALTERNATIF, self::RANK_NORMAL],
        ['alt rock',    self::ALTERNATIF, self::RANK_NORMAL],
        ['grunge',      self::ALTERNATIF, self::RANK_NORMAL],
        ['shoegaze',    self::ALTERNATIF, self::RANK_NORMAL],
        ['britpop',     self::ALTERNATIF, self::RANK_NORMAL],
        ['new wave',    self::ALTERNATIF, self::RANK_NORMAL],
        ['no wave',     self::ALTERNATIF, self::RANK_NORMAL],
        ['math rock',   self::ALTERNATIF, self::RANK_NORMAL],
        ['noise rock',  self::ALTERNATIF, self::RANK_NORMAL],
        ['art rock',    self::ALTERNATIF, self::RANK_NORMAL],
        ['post rock',   self::ALTERNATIF, self::RANK_NORMAL],
        ['dream pop',   self::ALTERNATIF, self::RANK_NORMAL],
        ['lo fi',       self::ALTERNATIF, self::RANK_NORMAL],

        // ── Rock ────────────────────────────────────────────────────────────
        ['rock and roll', self::ROCK, self::RANK_NORMAL],
        ['rock n roll',   self::ROCK, self::RANK_NORMAL],
        ['rockabilly',    self::ROCK, self::RANK_NORMAL],
        ['psychobilly',   self::ROCK, self::RANK_NORMAL],
        ['rock',          self::ROCK, self::RANK_NORMAL],

        // ── Pop ─────────────────────────────────────────────────────────────
        ['pop',        self::POP, self::RANK_NORMAL],
        ['synthpop',   self::POP, self::RANK_NORMAL],
        ['bubblegum',  self::POP, self::RANK_NORMAL],
        ['boy band',   self::POP, self::RANK_NORMAL],
        ['girl group', self::POP, self::RANK_NORMAL],
        ['adult contemporary', self::POP, self::RANK_NORMAL],

        // ── Électronique ────────────────────────────────────────────────────
        ['electronic',    self::ELECTRO, self::RANK_NORMAL],
        ['electronica',   self::ELECTRO, self::RANK_NORMAL],
        ['electro',       self::ELECTRO, self::RANK_NORMAL],
        ['electronique',  self::ELECTRO, self::RANK_NORMAL],
        ['techno',        self::ELECTRO, self::RANK_NORMAL],
        ['house',         self::ELECTRO, self::RANK_NORMAL],
        ['trance',        self::ELECTRO, self::RANK_NORMAL],
        ['edm',           self::ELECTRO, self::RANK_NORMAL],
        ['dubstep',       self::ELECTRO, self::RANK_NORMAL],
        ['drum and bass', self::ELECTRO, self::RANK_NORMAL],
        ['drum n bass',   self::ELECTRO, self::RANK_NORMAL],
        ['dnb',           self::ELECTRO, self::RANK_NORMAL],
        ['jungle',        self::ELECTRO, self::RANK_NORMAL],
        ['breakbeat',     self::ELECTRO, self::RANK_NORMAL],
        ['breakcore',     self::ELECTRO, self::RANK_NORMAL],
        ['idm',           self::ELECTRO, self::RANK_NORMAL],
        ['ambient',       self::ELECTRO, self::RANK_NORMAL],
        ['downtempo',     self::ELECTRO, self::RANK_NORMAL],
        ['trip hop',      self::ELECTRO, self::RANK_NORMAL],
        ['synthwave',     self::ELECTRO, self::RANK_NORMAL],
        ['vaporwave',     self::ELECTRO, self::RANK_NORMAL],
        ['chillwave',     self::ELECTRO, self::RANK_NORMAL],
        ['chiptune',      self::ELECTRO, self::RANK_NORMAL],
        ['8 bit',         self::ELECTRO, self::RANK_NORMAL],
        ['industrial',    self::ELECTRO, self::RANK_NORMAL],
        ['ebm',           self::ELECTRO, self::RANK_NORMAL],
        ['hardstyle',     self::ELECTRO, self::RANK_NORMAL],
        ['eurodance',     self::ELECTRO, self::RANK_NORMAL],
        ['dance',         self::ELECTRO, self::RANK_NORMAL],
        ['club',          self::ELECTRO, self::RANK_NORMAL],
        ['big beat',      self::ELECTRO, self::RANK_NORMAL],
        ['glitch',        self::ELECTRO, self::RANK_NORMAL],

        // ── Classique ───────────────────────────────────────────────────────
        ['classical',     self::CLASSIQUE, self::RANK_NORMAL],
        ['classique',     self::CLASSIQUE, self::RANK_NORMAL],
        ['baroque',       self::CLASSIQUE, self::RANK_NORMAL],
        ['opera',         self::CLASSIQUE, self::RANK_NORMAL],
        ['symphony',      self::CLASSIQUE, self::RANK_NORMAL],
        ['symphonic',     self::CLASSIQUE, self::RANK_NORMAL],
        ['symphonique',   self::CLASSIQUE, self::RANK_NORMAL],
        ['orchestral',    self::CLASSIQUE, self::RANK_NORMAL],
        ['orchestra',     self::CLASSIQUE, self::RANK_NORMAL],
        ['orchestre',     self::CLASSIQUE, self::RANK_NORMAL],
        ['requiem',       self::CLASSIQUE, self::RANK_NORMAL],
        ['chamber music', self::CLASSIQUE, self::RANK_NORMAL],
        ['choral',        self::CLASSIQUE, self::RANK_NORMAL],
        ['chorale',       self::CLASSIQUE, self::RANK_NORMAL],
        ['gregorian',     self::CLASSIQUE, self::RANK_NORMAL],
        ['gregorien',     self::CLASSIQUE, self::RANK_NORMAL],
        ['cantata',       self::CLASSIQUE, self::RANK_NORMAL],
        ['concerto',      self::CLASSIQUE, self::RANK_NORMAL],
        ['sonata',        self::CLASSIQUE, self::RANK_NORMAL],
        ['sonate',        self::CLASSIQUE, self::RANK_NORMAL],
        ['medieval',      self::CLASSIQUE, self::RANK_NORMAL],
        ['renaissance',   self::CLASSIQUE, self::RANK_NORMAL],

        // ── Trames sonores ──────────────────────────────────────────────────
        ['soundtrack',   self::TRAMES, self::RANK_NORMAL],
        ['trame sonore', self::TRAMES, self::RANK_NORMAL],
        ['score',        self::TRAMES, self::RANK_NORMAL],
        ['film',         self::TRAMES, self::RANK_NORMAL],
        ['movie',        self::TRAMES, self::RANK_NORMAL],
        ['cinema',       self::TRAMES, self::RANK_NORMAL],
        ['musical',      self::TRAMES, self::RANK_NORMAL],
        ['musicals',     self::TRAMES, self::RANK_NORMAL],
        ['comedie musicale', self::TRAMES, self::RANK_NORMAL],
        ['video game',   self::TRAMES, self::RANK_NORMAL],
        ['game music',   self::TRAMES, self::RANK_NORMAL],
        ['broadway',     self::TRAMES, self::RANK_NORMAL],

        // ── Musique pour enfants ────────────────────────────────────────────
        ['children',  self::ENFANTS, self::RANK_NORMAL],
        ['childrens', self::ENFANTS, self::RANK_NORMAL],
        ['kids',      self::ENFANTS, self::RANK_NORMAL],
        ['enfants',   self::ENFANTS, self::RANK_NORMAL],
        ['jeunesse',  self::ENFANTS, self::RANK_NORMAL],
        ['comptine',  self::ENFANTS, self::RANK_NORMAL],
        ['comptines', self::ENFANTS, self::RANK_NORMAL],
        ['berceuse',  self::ENFANTS, self::RANK_NORMAL],
        ['lullaby',   self::ENFANTS, self::RANK_NORMAL],
        ['nursery',   self::ENFANTS, self::RANK_NORMAL],

        // ── Musique du monde ────────────────────────────────────────────────
        ['world music', self::MONDE, self::RANK_NORMAL],
        ['worldbeat',   self::MONDE, self::RANK_NORMAL],
        ['latin',       self::MONDE, self::RANK_NORMAL],
        ['latino',      self::MONDE, self::RANK_NORMAL],
        ['salsa',       self::MONDE, self::RANK_NORMAL],
        ['reggaeton',   self::MONDE, self::RANK_NORMAL],
        ['cumbia',      self::MONDE, self::RANK_NORMAL],
        ['bachata',     self::MONDE, self::RANK_NORMAL],
        ['merengue',    self::MONDE, self::RANK_NORMAL],
        ['flamenco',    self::MONDE, self::RANK_NORMAL],
        ['bossa nova',  self::MONDE, self::RANK_NORMAL],
        ['samba',       self::MONDE, self::RANK_NORMAL],
        ['tango',       self::MONDE, self::RANK_NORMAL],
        ['mariachi',    self::MONDE, self::RANK_NORMAL],
        ['afrobeat',    self::MONDE, self::RANK_NORMAL],
        ['afro',        self::MONDE, self::RANK_NORMAL],
        ['african',     self::MONDE, self::RANK_NORMAL],
        ['africaine',   self::MONDE, self::RANK_NORMAL],
        ['klezmer',     self::MONDE, self::RANK_NORMAL],
        ['polka',       self::MONDE, self::RANK_NORMAL],
        ['zydeco',      self::MONDE, self::RANK_NORMAL],
        ['cajun',       self::MONDE, self::RANK_NORMAL],
        ['calypso',     self::MONDE, self::RANK_NORMAL],
        ['soca',        self::MONDE, self::RANK_NORMAL],
        ['middle eastern', self::MONDE, self::RANK_NORMAL],
        ['arabic',      self::MONDE, self::RANK_NORMAL],
        ['native american', self::MONDE, self::RANK_NORMAL],
        ['first nations',   self::MONDE, self::RANK_NORMAL],
        ['autochtone',  self::MONDE, self::RANK_NORMAL],
        ['inuit',       self::MONDE, self::RANK_NORMAL],
        ['powwow',      self::MONDE, self::RANK_NORMAL],
        ['throat singing', self::MONDE, self::RANK_NORMAL],

        // ── Les genres d'ici (rang fort) ────────────────────────────────────
        ['neo trad',     self::TRAD, self::RANK_STRONG],
        ['neotrad',      self::TRAD, self::RANK_STRONG],
        ['trad',         self::TRAD, self::RANK_STRONG],
        ['traditionnel', self::TRAD, self::RANK_STRONG],
        ['traditionnelle', self::TRAD, self::RANK_STRONG],
        // « traditional » seul, après que « traditional folk/country/pop »
        // aient déjà trouvé preneur plus haut.
        ['traditional',  self::TRAD, self::RANK_STRONG],
        ['folklore',     self::TRAD, self::RANK_STRONG],
        ['folklorique',  self::TRAD, self::RANK_STRONG],
        ['turlutte',     self::TRAD, self::RANK_STRONG],
        ['terroir',      self::TRAD, self::RANK_STRONG],

        ['acadien',   self::ACADIEN, self::RANK_STRONG],
        ['acadienne', self::ACADIEN, self::RANK_STRONG],
        ['acadian',   self::ACADIEN, self::RANK_STRONG],
        ['acadie',    self::ACADIEN, self::RANK_STRONG],
        ['chiac',     self::ACADIEN, self::RANK_STRONG],

        ['chanson',   self::CHANSON, self::RANK_STRONG],
        ['chansons',  self::CHANSON, self::RANK_STRONG],
        ['variete',   self::CHANSON, self::RANK_STRONG],
        ['chansonnier', self::CHANSON, self::RANK_STRONG],
        ['auteur compositeur interprete', self::CHANSON, self::RANK_STRONG],

        // ── Indices de langue / provenance : à défaut de mieux ──────────────
        ['quebecois',  self::CHANSON, self::RANK_WEAK],
        ['quebecoise', self::CHANSON, self::RANK_WEAK],
        ['francophone', self::CHANSON, self::RANK_WEAK],
        ['francais',   self::CHANSON, self::RANK_WEAK],
        ['francaise',  self::CHANSON, self::RANK_WEAK],
        ['french',     self::CHANSON, self::RANK_WEAK],
        ['france',     self::CHANSON, self::RANK_WEAK],
        ['quebec',     self::CHANSON, self::RANK_WEAK],
        ['south america', self::MONDE, self::RANK_WEAK],
        ['africa',     self::MONDE, self::RANK_WEAK],
        ['asia',       self::MONDE, self::RANK_WEAK],
        ['caribbean',  self::MONDE, self::RANK_WEAK],
        ['middle east', self::MONDE, self::RANK_WEAK],
    ];

    /** Départage deux genres d'ici à égalité de votes : le plus précis gagne. */
    private const STRONG_ORDER = [self::ACADIEN, self::TRAD, self::CHANSON];

    private const ACCENTS = [
        'à' => 'a', 'â' => 'a', 'ä' => 'a', 'á' => 'a', 'ã' => 'a', 'å' => 'a',
        'ç' => 'c', 'é' => 'e', 'è' => 'e', 'ê' => 'e', 'ë' => 'e',
        'î' => 'i', 'ï' => 'i', 'í' => 'i', 'ì' => 'i',
        'ô' => 'o', 'ö' => 'o', 'ó' => 'o', 'ò' => 'o', 'õ' => 'o', 'ø' => 'o',
        'ù' => 'u', 'û' => 'u', 'ü' => 'u', 'ú' => 'u',
        'ÿ' => 'y', 'ñ' => 'n', 'œ' => 'oe', 'æ' => 'ae', 'ß' => 'ss',
    ];

    /**
     * Forme comparable d'une étiquette : minuscules, sans accent, sans
     * ponctuation, mots séparés par une seule espace. Le préfixe numérique
     * des vieux tags ID3v1 (« (13)Pop ») saute au passage.
     */
    public static function normalize(string $raw): string
    {
        $s = trim($raw);
        $s = preg_replace('/^\(\d+\)\s*/', '', $s);
        $s = mb_strtolower($s, 'UTF-8');
        $s = strtr($s, self::ACCENTS);
        $s = str_replace('&', ' and ', $s);
        $s = preg_replace('/[^a-z0-9]+/', ' ', $s);

        return trim(preg_replace('/\s+/', ' ', $s));
    }

    /** Une étiquette qui ne dit rien de la musique. */
    public static function isNoise(string $raw): bool
    {
        return in_array(self::normalize($raw), self::NOISE, true);
    }

    /**
     * Le genre canonique d'une étiquette, ou null si elle ne dit rien
     * d'exploitable.
     */
    public static function classify(string $raw): ?string
    {
        $match = self::match($raw);

        return $match['genre'] ?? null;
    }

    /**
     * Comme classify(), mais rend aussi le rang de la règle qui a répondu
     * (voir pickFromTags). Rend null si rien ne correspond.
     *
     * @return array{genre: string, rank: int}|null
     */
    public static function match(string $raw): ?array
    {
        $n = self::normalize($raw);
        if ($n === '' || in_array($n, self::NOISE, true)) return null;

        $exact = self::exactMap();
        if (isset($exact[$n])) {
            // Un alias exact vaut la règle du même genre : les genres d'ici
            // gardent leur rang fort.
            return ['genre' => $exact[$n], 'rank' => self::rankOf($exact[$n])];
        }

        foreach (self::RULES as [$phrase, $genre, $rank]) {
            if (self::hasWords($n, $phrase)) {
                return ['genre' => $genre, 'rank' => $rank];
            }
        }

        return null;
    }

    /**
     * Le meilleur genre d'une liste d'étiquettes pondérées (les tags d'un
     * artiste chez MusicBrainz, ou les genres ID3 de ses fichiers).
     *
     * La règle : le genre le plus voté l'emporte, sauf qu'un genre d'ici
     * (chanson, trad, acadien) l'emporte dès qu'il fait jeu égal — « rock » se
     * dit de tout le monde, « néo-trad » ne se dit pas par hasard. Les indices
     * de langue ne servent que si rien d'autre ne ressort.
     *
     * @param array<array{name: string, count: int}> $tags
     */
    public static function pickFromTags(array $tags): ?string
    {
        $best = []; // rang => ['genre' => …, 'count' => …]

        foreach ($tags as $tag) {
            $name = (string)($tag['name'] ?? '');
            if ($name === '') continue;
            $match = self::match($name);
            if (!$match) continue;

            $count = max(0, (int)($tag['count'] ?? 0));
            $rank  = $match['rank'];
            $prev  = $best[$rank] ?? null;

            if ($prev === null
                || $count > $prev['count']
                || ($count === $prev['count'] && self::strongerThan($match['genre'], $prev['genre']))
            ) {
                $best[$rank] = ['genre' => $match['genre'], 'count' => $count];
            }
        }

        $strong = $best[self::RANK_STRONG] ?? null;
        $normal = $best[self::RANK_NORMAL] ?? null;

        if ($strong && (!$normal || $strong['count'] >= $normal['count'])) {
            return $strong['genre'];
        }
        if ($normal) return $normal['genre'];
        if ($strong) return $strong['genre'];

        return $best[self::RANK_WEAK]['genre'] ?? null;
    }

    /** Le genre fait-il partie de la liste ? */
    public static function isCanonical(string $genre): bool
    {
        return in_array($genre, self::ALL, true);
    }

    // ── Interne ─────────────────────────────────────────────────────────────

    /** Le rang naturel d'un genre : les genres d'ici pèsent plus lourd. */
    private static function rankOf(string $genre): int
    {
        return in_array($genre, self::STRONG_ORDER, true)
            ? self::RANK_STRONG
            : self::RANK_NORMAL;
    }

    /** Départage deux genres d'ici (Acadien > Trad > Chanson). */
    private static function strongerThan(string $a, string $b): bool
    {
        $ia = array_search($a, self::STRONG_ORDER, true);
        $ib = array_search($b, self::STRONG_ORDER, true);
        if ($ia === false || $ib === false) return false;

        return $ia < $ib;
    }

    /** Alias exact => genre, normalisé une fois pour toutes. */
    private static function exactMap(): array
    {
        static $map = null;
        if ($map !== null) return $map;

        $map = [];
        foreach (self::ALL as $genre) {
            $map[self::normalize($genre)] = $genre;
        }
        foreach (self::EXACT as $genre => $aliases) {
            foreach ($aliases as $alias) {
                $map[self::normalize($alias)] = $genre;
            }
        }

        return $map;
    }

    /** L'expression apparaît-elle en mots entiers dans la forme normalisée ? */
    private static function hasWords(string $haystack, string $phrase): bool
    {
        return (bool)preg_match(
            '/(?:^| )' . preg_quote($phrase, '/') . '(?: |$)/',
            $haystack
        );
    }
}

<?php
/**
 * Vérifie la taxonomie de genres (src/GenreTaxonomy.php).
 *
 * Aucune base, aucun réseau : que des étiquettes en entrée et le genre
 * attendu en sortie. Les cas viennent de la vraie bibliothèque (étiquettes
 * ID3 trouvées dans les fichiers, tags MusicBrainz) et des pièges connus du
 * classement par mots (« melodic death metal » n'est pas du folk, « metal
 * québécois » n'est pas de la chanson).
 *
 *   php scripts/test-genre-taxonomy.php
 */

require_once __DIR__ . '/../src/GenreTaxonomy.php';

$failures = 0;
$checks   = 0;

function check(string $label, mixed $got, mixed $want): void
{
    global $failures, $checks;
    $checks++;
    if ($got === $want) return;
    $failures++;
    printf(
        "  ✗ %s\n      attendu : %s\n      obtenu  : %s\n",
        $label,
        var_export($want, true),
        var_export($got, true)
    );
}

// ── Une étiquette, un genre ───────────────────────────────────────────────────
$cases = [
    // Les noms canoniques se reclassent sur eux-mêmes (idempotence).
    'Chanson québécoise/francophone' => GenreTaxonomy::CHANSON,
    'Alternatif / Indie'             => GenreTaxonomy::ALTERNATIF,
    'Hip-hop / Rap'                  => GenreTaxonomy::HIPHOP,
    'R&B / Soul'                     => GenreTaxonomy::RNB,
    'Métal'                          => GenreTaxonomy::METAL,
    'Électronique'                   => GenreTaxonomy::ELECTRO,
    'Trames sonores'                 => GenreTaxonomy::TRAMES,

    // Les valeurs présentes en base avant la reclassification.
    'Punk Rock'            => GenreTaxonomy::PUNK,
    'Ska'                  => GenreTaxonomy::PUNK,
    'Melodic Hardcore'     => GenreTaxonomy::PUNK,
    'Post-hardcore'        => GenreTaxonomy::PUNK,
    'Hardcore Punk'        => GenreTaxonomy::PUNK,
    'Midwest Emo'          => GenreTaxonomy::PUNK,
    'Emo & Hardcore'       => GenreTaxonomy::PUNK,
    'Celtic Punk'          => GenreTaxonomy::PUNK,
    'Alternative & Punk'   => GenreTaxonomy::PUNK,
    'Melodic Death Metal'  => GenreTaxonomy::METAL,
    'Melodic Black Metal'  => GenreTaxonomy::METAL,
    'Metal & Hard Rock'    => GenreTaxonomy::METAL,
    'Alternative Metal'    => GenreTaxonomy::METAL,
    'Metalcore'            => GenreTaxonomy::METAL,
    'Nu Metal'             => GenreTaxonomy::METAL,
    'Post-metal'           => GenreTaxonomy::METAL,
    'Indie'                => GenreTaxonomy::ALTERNATIF,
    'Alt. Rock'            => GenreTaxonomy::ALTERNATIF,
    'New Wave'             => GenreTaxonomy::ALTERNATIF,
    'Classic Rock'         => GenreTaxonomy::ROCK,
    'Soft Rock'            => GenreTaxonomy::ROCK,
    'Rock/Pop'             => GenreTaxonomy::ROCK,
    'Retrospective Pop'    => GenreTaxonomy::POP,
    'General Pop'          => GenreTaxonomy::POP,
    'Dance Pop'            => GenreTaxonomy::POP,
    'Dance'                => GenreTaxonomy::ELECTRO,
    'IDM'                  => GenreTaxonomy::ELECTRO,
    'Chiptune'             => GenreTaxonomy::ELECTRO,
    'Post-industrial'      => GenreTaxonomy::ELECTRO,
    'Industrial'           => GenreTaxonomy::ELECTRO,
    'Hip Hop'              => GenreTaxonomy::HIPHOP,
    'Hip-Hop'              => GenreTaxonomy::HIPHOP,
    'Country & Folk'       => GenreTaxonomy::COUNTRY,
    'Bluegrass'            => GenreTaxonomy::COUNTRY,
    'Contemporary Folk'    => GenreTaxonomy::FOLK,
    'Acoustic'             => GenreTaxonomy::FOLK,
    'Blues'                => GenreTaxonomy::BLUES,
    'Jazz'                 => GenreTaxonomy::JAZZ,
    'Classical'            => GenreTaxonomy::CLASSIQUE,
    'Musical'              => GenreTaxonomy::TRAMES,
    'Film'                 => GenreTaxonomy::TRAMES,
    'Native American'      => GenreTaxonomy::MONDE,
    'Latin'                => GenreTaxonomy::MONDE,
    'Contemporary Christian' => GenreTaxonomy::GOSPEL,
    'Reggae'               => GenreTaxonomy::REGGAE,

    // Les genres d'ici.
    'Néo-trad'             => GenreTaxonomy::TRAD,
    'Folklore'             => GenreTaxonomy::TRAD,
    'Musique traditionnelle' => GenreTaxonomy::TRAD,
    'Chanson québécoise'   => GenreTaxonomy::CHANSON,
    'Musique francophone'  => GenreTaxonomy::CHANSON,
    'Auteur-interprète'    => GenreTaxonomy::CHANSON,
    'Variété française'    => GenreTaxonomy::CHANSON,
    'Français'             => GenreTaxonomy::CHANSON,
    'Québécois'            => GenreTaxonomy::CHANSON,
    'Musique acadienne'    => GenreTaxonomy::ACADIEN,
    'Chiac'                => GenreTaxonomy::ACADIEN,

    // Vieux tags ID3v1 numérotés.
    '(13)Pop'              => GenreTaxonomy::POP,
    '(17)Rock'             => GenreTaxonomy::ROCK,

    // Le plus précis gagne, quel que soit le mot large qu'il contient.
    'folk rock'            => GenreTaxonomy::FOLK,
    'blues rock'           => GenreTaxonomy::BLUES,
    'country rock'         => GenreTaxonomy::COUNTRY,
    'pop rock'             => GenreTaxonomy::POP,
    'indie rock'           => GenreTaxonomy::ALTERNATIF,
    'post punk'            => GenreTaxonomy::ALTERNATIF,
    'hard rock'            => GenreTaxonomy::ROCK,
    'christian metal'      => GenreTaxonomy::METAL,
    'ska punk'             => GenreTaxonomy::PUNK,
    'rhythm and blues'     => GenreTaxonomy::RNB,
    'soul blues'           => GenreTaxonomy::RNB,
    'trad jazz'            => GenreTaxonomy::JAZZ,
    'traditional folk'     => GenreTaxonomy::FOLK,
    'traditional country'  => GenreTaxonomy::COUNTRY,
    'Traditional'          => GenreTaxonomy::TRAD,
    // Un adjectif de provenance ne change pas le genre.
    'metal québécois'      => GenreTaxonomy::METAL,
    'rock français'        => GenreTaxonomy::ROCK,
    'rap québécois'        => GenreTaxonomy::HIPHOP,

    // Les étiquettes des catalogues consultés à défaut de MusicBrainz
    // (src/GenreLookup.php) : Deezer range par rayons, Apple Music donne un
    // genre principal par artiste.
    'Chanson française'    => GenreTaxonomy::CHANSON,
    'French Pop'           => GenreTaxonomy::CHANSON,   // l'étiquette d'ici chez Apple Music
    'Canadian French Pop'  => GenreTaxonomy::CHANSON,
    'Rap français'         => GenreTaxonomy::HIPHOP,
    'Rap/Hip Hop'          => GenreTaxonomy::HIPHOP,
    'Soul & Funk'          => GenreTaxonomy::RNB,
    'Pop indé/Folk'        => GenreTaxonomy::FOLK,
    'Films/Jeux vidéo'     => GenreTaxonomy::TRAMES,
    'Jeunesse'             => GenreTaxonomy::ENFANTS,
    'Comptines/Chansons'   => GenreTaxonomy::ENFANTS,
    'Musique africaine'    => GenreTaxonomy::MONDE,
    'Musique asiatique'    => GenreTaxonomy::MONDE,
    'Musique brésilienne'  => GenreTaxonomy::MONDE,
    'Musique indienne'     => GenreTaxonomy::MONDE,
    'Singer/Songwriter'    => GenreTaxonomy::FOLK,
    'Children\'s Music'    => GenreTaxonomy::ENFANTS,
    'Hip-Hop/Rap'          => GenreTaxonomy::HIPHOP,
    // Ce que ces catalogues rangent avec la musique sans en être.
    'Livres audio'         => null,
    'Histoires'            => null,
    'Musique allemande'    => null,

    // Rien d'exploitable : aucun genre plutôt qu'un faux genre.
    'Music'                => null,
    'Miscellaneous'        => null,
    'Other'                => null,
    'Various Artists'      => null,
    'Special Purpose Artist' => null,
    'Western Europe'       => null,
    'Oldies'               => null,
    'Instrumental'         => null,
    'Canadian'             => null,
    '90s'                  => null,
    'seen live'            => null,
    'Noquarterpunk'        => null,
    'Church Core'          => null,
    ''                     => null,
    '   '                  => null,
];

echo "Étiquettes → genre\n";
foreach ($cases as $raw => $want) {
    check("« $raw »", GenreTaxonomy::classify((string)$raw), $want);
}

// ── Tout genre rendu appartient à la liste ────────────────────────────────────
foreach ($cases as $raw => $want) {
    $got = GenreTaxonomy::classify((string)$raw);
    if ($got !== null) {
        check("« $raw » est dans la liste", GenreTaxonomy::isCanonical($got), true);
    }
}

// ── Choix parmi plusieurs étiquettes pondérées ────────────────────────────────
echo "Choix parmi des tags pondérés\n";

$tagCases = [
    // Les Cowboys Fringants : folk et néo-trad à égalité → le genre d'ici gagne.
    'Les Cowboys Fringants' => [
        [['name' => 'folk', 'count' => 4], ['name' => 'néo-trad', 'count' => 4],
         ['name' => 'folk rock', 'count' => 3], ['name' => 'chanson québécoise', 'count' => 2],
         ['name' => 'rock', 'count' => 1]],
        GenreTaxonomy::TRAD,
    ],
    // Mes Aïeux : néo-trad (fort) contre folk québécois (normal), à égalité.
    'Mes Aïeux' => [
        [['name' => 'folk québécois', 'count' => 1], ['name' => 'néo-trad', 'count' => 1]],
        GenreTaxonomy::TRAD,
    ],
    // Un groupe punk d'ici reste punk : la chanson ne l'emporte pas sur un
    // genre nettement plus voté.
    'punk québécois' => [
        [['name' => 'punk', 'count' => 5], ['name' => 'chanson québécoise', 'count' => 1]],
        GenreTaxonomy::PUNK,
    ],
    // Lisa LeBlanc : rien de régional dans les tags → folk.
    'Lisa LeBlanc' => [
        [['name' => 'folk', 'count' => 1], ['name' => 'singer-songwriter', 'count' => 1],
         ['name' => 'trash folk', 'count' => 1]],
        GenreTaxonomy::FOLK,
    ],
    // P'tit Belliveau : un seul tag exploitable.
    "P'tit Belliveau" => [
        [['name' => 'indie', 'count' => 1]],
        GenreTaxonomy::ALTERNATIF,
    ],
    // Le bruit est ignoré, le genre du dessous ressort.
    'bruit + genre' => [
        [['name' => 'seen live', 'count' => 9], ['name' => 'various', 'count' => 7],
         ['name' => 'metal', 'count' => 2]],
        GenreTaxonomy::METAL,
    ],
    // L'indice de langue ne sert qu'à défaut de mieux.
    'langue seule' => [
        [['name' => 'français', 'count' => 3], ['name' => 'seen live', 'count' => 8]],
        GenreTaxonomy::CHANSON,
    ],
    'langue + genre' => [
        [['name' => 'français', 'count' => 9], ['name' => 'metal', 'count' => 1]],
        GenreTaxonomy::METAL,
    ],
    // Acadien passe devant les autres genres d'ici à égalité.
    'acadien + chanson' => [
        [['name' => 'chanson', 'count' => 2], ['name' => 'acadien', 'count' => 2]],
        GenreTaxonomy::ACADIEN,
    ],
    'rien d\'exploitable' => [
        [['name' => 'seen live', 'count' => 4], ['name' => 'canadian', 'count' => 2]],
        null,
    ],
    'aucun tag' => [[], null],
];

foreach ($tagCases as $label => [$tags, $want]) {
    check($label, GenreTaxonomy::pickFromTags($tags), $want);
}

// ── Plusieurs genres par artiste ──────────────────────────────────────────────
echo "Plusieurs genres\n";
$t = fn(array $pairs) => array_map(fn($k, $v) => ['name' => $k, 'count' => $v], array_keys($pairs), $pairs);
$manyCases = [
    // Le profil Last.fm d'un groupe d'ici : folk ET rock, l'origine à part.
    'folk + rock + quebec' => [
        $t(['folk' => 100, 'quebec' => 90, 'rock' => 70, 'francophone' => 40, 'seen live' => 10]),
        [GenreTaxonomy::FOLK, GenreTaxonomy::ROCK],
    ],
    // Un genre trop faible à côté ne compte pas.
    'secondaire sous le seuil' => [
        $t(['rock' => 100, 'pop' => 20]),
        [GenreTaxonomy::ROCK],
    ],
    // Trois au plus, le principal en tête.
    'plafond de trois' => [
        $t(['hip hop' => 100, 'rnb' => 90, 'pop' => 80, 'electronic' => 70, 'jazz' => 60]),
        [GenreTaxonomy::HIPHOP, GenreTaxonomy::RNB, GenreTaxonomy::POP],
    ],
    // Une langue n'ajoute jamais un genre.
    'langue écartée' => [
        $t(['metal' => 100, 'french' => 90]),
        [GenreTaxonomy::METAL],
    ],
    // Deux étiquettes du même genre n'en font qu'un.
    'même genre deux fois' => [
        $t(['punk rock' => 100, 'punk' => 90, 'hardcore punk' => 80]),
        [GenreTaxonomy::PUNK],
    ],
    'rien' => [$t(['seen live' => 100]), []],
];
foreach ($manyCases as $label => [$tags, $want]) {
    check($label, GenreTaxonomy::pickManyFromTags($tags), $want);
    // Le principal est toujours celui de pickFromTags.
    check("$label (principal)", GenreTaxonomy::pickManyFromTags($tags)[0] ?? null, GenreTaxonomy::pickFromTags($tags));
}

// ── L'origine ─────────────────────────────────────────────────────────────────
echo "Origine\n";
require_once __DIR__ . '/../src/Origine.php';
$origineCases = [
    'quebec + canadian' => [$t(['folk' => 100, 'canadian' => 80, 'quebec' => 60]), Origine::QUEBEC],
    'québécois accentué' => [$t(['Québécois' => 100]), Origine::QUEBEC],
    'canadian seul' => [$t(['indie' => 100, 'canadian' => 70]), Origine::CANADA],
    'french' => [$t(['chanson' => 100, 'french' => 60]), Origine::FRANCE],
    'acadien' => [$t(['folk' => 100, 'acadian' => 50, 'canada' => 40]), Origine::ACADIE],
    'le plus voté' => [$t(['rock' => 100, 'british' => 80, 'american' => 20]), Origine::ROYAUME_UNI],
    'vote isolé ignoré' => [$t(['rock' => 100, 'pop' => 90, 'indie' => 80, 'french' => 2]), null],
    'aucune' => [$t(['rock' => 100]), null],
];
foreach ($origineCases as $label => [$tags, $want]) {
    check($label, Origine::depuisTags($tags), $want);
}
$mbCases = [
    'ville du Québec' => [['country' => 'CA', 'area' => ['name' => 'Montréal']], Origine::QUEBEC],
    'province' => [['country' => 'CA', 'area' => ['name' => 'Quebec', 'iso-3166-2-codes' => ['CA-QC']]], Origine::QUEBEC],
    'ville natale' => [['country' => 'CA', 'area' => ['name' => 'Canada'], 'begin-area' => ['name' => 'Trois-Rivières']], Origine::QUEBEC],
    'Moncton' => [['country' => 'CA', 'begin-area' => ['name' => 'Moncton']], Origine::ACADIE],
    'Toronto' => [['country' => 'CA', 'area' => ['name' => 'Toronto']], Origine::CANADA],
    'pays seul' => [['country' => 'FR'], Origine::FRANCE],
    'pays par la région' => [['area' => ['name' => 'Belgium', 'iso-3166-1-codes' => ['BE']]], Origine::BELGIQUE],
    'pays inconnu' => [['country' => 'XW'], null],
    'rien' => [[], null],
];
foreach ($mbCases as $label => [$fiche, $want]) {
    check("MusicBrainz : $label", Origine::depuisMusicBrainz($fiche), $want);
}
check('canonique', Origine::canonique('quebec'), Origine::QUEBEC);
check('canonique inconnue', Origine::canonique('Atlantide'), null);

// ── Bilan ─────────────────────────────────────────────────────────────────────
echo "\n";
if ($failures === 0) {
    echo "✓ {$checks} vérifications, aucune erreur.\n";
    exit(0);
}
echo "✗ {$failures} erreur(s) sur {$checks} vérifications.\n";
exit(1);

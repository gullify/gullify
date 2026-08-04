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

// ── Bilan ─────────────────────────────────────────────────────────────────────
echo "\n";
if ($failures === 0) {
    echo "✓ {$checks} vérifications, aucune erreur.\n";
    exit(0);
}
echo "✗ {$failures} erreur(s) sur {$checks} vérifications.\n";
exit(1);

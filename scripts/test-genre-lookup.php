<?php
/**
 * Vérifie le garde-fou de la recherche d'artiste (src/MusicBrainz.php), sur
 * lequel s'appuient toutes les sources de genres (src/GenreLookup.php).
 *
 * Aucune base, aucun réseau : deux noms en entrée, « c'est le même » ou non en
 * sortie. Les cas viennent de la vraie bibliothèque — un mauvais artiste, et
 * c'est toute une discographie rangée de travers.
 *
 *   php scripts/test-genre-lookup.php
 */

require_once __DIR__ . '/../src/GenreLookup.php';

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

echo "Correspondance de noms d'artistes\n";

// [nom cherché, nom trouvé, confiance de la source, même artiste ?]
$cases = [
    // Le même nom, à la casse, aux accents et à la ponctuation près.
    ['Kaïn',            'Kaïn',            0,   true],
    ['Kaïn',            'KAIN',            0,   true],
    ['UB-40',           'UB40',            0,   true],
    ['Les Trois Accords', 'les trois accords', 0, true],

    // Un nom contenu dans l'autre : le préfixe de compilation qui traîne dans
    // les noms de fichiers, la mention qui suit un nom de groupe.
    ['(50 First Dates) Bob Marley', 'Bob Marley', 0, true],
    ['Beau Dommage',    'Beau Dommage (live)', 0, true],

    // Le piège : un nom court avalé par un long. MusicBrainz note pourtant le
    // groupe « XYZ » 100 sur une recherche qui n'a rien à voir.
    ['Anonyme Introuvable XYZ', 'XYZ',      100, false],
    ['Kaïn',            'Kain Cioffie',    100, false],
    ['La Chicane',      'Chic',            100, false],

    // Un autre artiste, même quand la source se dit sûre d'elle.
    ['Les Cowboys Fringants', 'The Cowboys', 100, false],
    ['Mes Aïeux',       'Les Aieux du Nord', 95, false],

    // La confiance de la source n'ouvre la porte qu'aux fautes de frappe.
    ['Vilain Pingouin', 'Vilain Pingoin',  100, true],
    ['Vilain Pingouin', 'Vilain Pingouin', 0,   true],
    ['Vilain Pingouin', 'Vilain Pingoin',  50,  false],

    // Rien à comparer.
    ['',                'Quelqu\'un',      100, false],
    ['Quelqu\'un',      '',                100, false],
];

foreach ($cases as [$wanted, $found, $score, $want]) {
    check("« $wanted » ≟ « $found » ($score)", MusicBrainz::sameArtist($wanted, $found, $score), $want);
}

// ── Bilan ─────────────────────────────────────────────────────────────────────
echo "\n";
if ($failures === 0) {
    echo "✓ {$checks} vérifications, aucune erreur.\n";
    exit(0);
}
echo "✗ {$failures} erreur(s) sur {$checks} vérifications.\n";
exit(1);

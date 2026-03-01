<?php
/**
 * One-time script: Import genre taxonomy into Gullify DB.
 * Run once, then delete this file.
 */
require_once __DIR__ . '/../src/AppConfig.php';

$db = AppConfig::getDB();

// Check if already populated
$count = $db->query("SELECT COUNT(*) FROM genres")->fetchColumn();
if ($count > 0) {
    echo "Genres already populated ($count entries). Delete this file.\n";
    exit;
}

$genres = [
    'Alternative' => [
        'Art Punk', 'Alternative Rock', 'Britpunk', 'College Rock', 'Crossover Thrash',
        'Crust Punk', 'Emotional Hardcore', 'Experimental Rock', 'Folk Punk', 'Goth Rock',
        'Gothic Rock', 'Grunge', 'Hardcore Punk', 'Hard Rock', 'Indie Rock', 'Lo-fi',
        'Musique Concrète', 'New Wave', 'Progressive Rock', 'Punk', 'Shoegaze', 'Steampunk'
    ],
    'Anime' => [],
    'Blues' => [
        'Acoustic Blues', 'African Blues', 'Blues Rock', 'Blues Shouter', 'British Blues',
        'Canadian Blues', 'Chicago Blues', 'Classic Blues', 'Classic Female Blues',
        'Contemporary Blues', 'Country Blues', 'Dark Blues', 'Delta Blues', 'Detroit Blues',
        'Doom Blues', 'Electric Blues', 'Folk Blues', 'Gospel Blues', 'Harmonica Blues',
        'Hill Country Blues', 'Hokum Blues', 'Jazz Blues', 'Jump Blues', 'Kansas City Blues',
        'Louisiana Blues', 'Memphis Blues', 'Modern Blues', 'New Orleans Blues', 'NY Blues',
        'Piano Blues', 'Piedmont Blues', 'Punk Blues', 'Ragtime Blues', 'Rhythm Blues',
        'Soul Blues', 'St. Louis Blues', 'Swamp Blues', 'Texas Blues', 'Urban Blues',
        'Vaudeville Blues', 'West Coast Blues', 'Zydeco Blues'
    ],
    'Children\'s Music' => ['Lullabies', 'Sing-Along', 'Stories'],
    'Classical' => [
        'Avant-Garde Classical', 'Ballet', 'Baroque', 'Cantata', 'Chamber Music', 'Chant',
        'Choral', 'Classical Crossover', 'Concerto', 'Concerto Grosso', 'Contemporary Classical',
        'Early Music', 'Expressionist', 'High Classical', 'Impressionist', 'Mass Requiem',
        'Medieval', 'Minimalism', 'Modern Composition', 'Modern Classical', 'Opera', 'Oratorio',
        'Orchestral', 'Organum', 'Renaissance', 'Romantic', 'Sonata', 'Symphonic', 'Symphony',
        'Twelve-tone', 'Wedding Music'
    ],
    'Comedy' => ['Novelty', 'Parody Music', 'Stand-up Comedy', 'Vaudeville'],
    'Country' => [
        'Alternative Country', 'Americana', 'Australian Country', 'Bakersfield Sound',
        'Bluegrass', 'Blues Country', 'Christian Country', 'Classic Country', 'Close Harmony',
        'Contemporary Bluegrass', 'Contemporary Country', 'Country Gospel', 'Country Pop',
        'Country Rap', 'Country Rock', 'Country Soul', 'Cowboy', 'Western', 'Cowpunk',
        'Honky Tonk', 'Nashville Sound', 'Neotraditional Country', 'Outlaw Country',
        'Progressive Country', 'Psychobilly', 'Punkabilly', 'Red Dirt', 'Texas Country',
        'Traditional Bluegrass', 'Traditional Country', 'Western Swing', 'Zydeco'
    ],
    'Dance' => [
        'Club Dance', 'Breakcore', 'Breakbeat', 'Brostep', 'Chillstep', 'Deep House',
        'Dubstep', 'Electro House', 'Electroswing', 'Future Garage', 'Garage', 'Glitch Hop',
        'Grime', 'Hardcore', 'Hard Dance', 'Hi-NRG', 'Eurodance', 'House', 'Jungle',
        'Drum\'n\'bass', 'Speedcore', 'Techno', 'Trance', 'Trap'
    ],
    'Disney' => [],
    'Easy Listening' => [
        'Background Music', 'Bop', 'Elevator Music', 'Lounge', 'Middle of the Road', 'Swing'
    ],
    'Electronic' => [
        '8bit', 'Chiptune', 'Ambient', 'Bassline', 'Chillwave', 'Downtempo', 'Drum & Bass',
        'Electro', 'Electro-swing', 'Electroacoustic', 'Electronica', 'Electronic Rock',
        'Hardstyle', 'IDM', 'Experimental Electronic', 'Industrial', 'Trip Hop', 'Vaporwave',
        'UK Garage'
    ],
    'Folk' => [
        'American Folk Revival', 'Anti-Folk', 'British Folk Revival', 'Contemporary Folk',
        'Freak Folk', 'Indie Folk', 'Neofolk', 'Progressive Folk', 'Psychedelic Folk',
        'Traditional Folk'
    ],
    'French Pop' => [],
    'Fitness & Workout' => [],
    'Hip-Hop' => [
        'Alternative Rap', 'Bounce', 'Christian Hip Hop', 'Conscious Hip Hop', 'Dirty South',
        'East Coast Hip-Hop', 'Freestyle Rap', 'G-Funk', 'Gangsta Rap', 'Golden Age Hip-Hop',
        'Grime', 'Hardcore Rap', 'Hip Pop', 'Horrorcore', 'Hyphy', 'Industrial Hip Hop',
        'Instrumental Hip Hop', 'Jazz Rap', 'Latin Rap', 'Midwest Hip Hop', 'Nerdcore',
        'New Jack Swing', 'Old School Rap', 'Trap', 'Turntablism', 'Underground Rap',
        'West Coast Rap'
    ],
    'Holiday' => ['Chanukah', 'Christmas', 'Easter', 'Halloween', 'Thanksgiving'],
    'Indie Pop' => [],
    'Industrial' => [
        'Aggrotech', 'Coldwave', 'Dark Electro', 'Death Industrial', 'Electro-Industrial',
        'Electronic Body Music', 'Industrial Metal', 'Industrial Rock', 'Noise', 'Witch House'
    ],
    'Inspirational' => [
        'CCM', 'Christian Metal', 'Christian Pop', 'Christian Rap', 'Christian Rock',
        'Contemporary Gospel', 'Gospel', 'Praise & Worship', 'Southern Gospel', 'Traditional Gospel'
    ],
    'Instrumental' => ['March', 'Marching Band'],
    'J-Pop' => ['J-Rock', 'J-Synth', 'J-Ska', 'J-Punk'],
    'Jazz' => [
        'Acid Jazz', 'Afro-Cuban Jazz', 'Avant-Garde Jazz', 'Bebop', 'Big Band',
        'Chamber Jazz', 'Contemporary Jazz', 'Cool Jazz', 'Dark Jazz', 'Dixieland',
        'Early Jazz', 'Free Jazz', 'Fusion', 'Gypsy Jazz', 'Hard Bop', 'Jazz-Funk',
        'Jazz-Fusion', 'Jazz Rap', 'Jazz Rock', 'Latin Jazz', 'Mainstream Jazz',
        'Modal Jazz', 'Neo-Bop', 'Nu Jazz', 'Orchestral Jazz', 'Post-Bop', 'Ragtime',
        'Ska Jazz', 'Smooth Jazz', 'Soul Jazz', 'Swing Jazz', 'Trad Jazz', 'West Coast Jazz'
    ],
    'K-Pop' => [],
    'Latin' => [
        'Bachata', 'Bossa Nova', 'Brazilian', 'Cumbia', 'Flamenco', 'Latin Jazz',
        'Mambo', 'Mariachi', 'Merengue', 'Pop Latino', 'Reggaeton', 'Salsa', 'Soca',
        'Tango', 'Vallenato', 'Zouk'
    ],
    'Metal' => [
        'Heavy Metal', 'Speed Metal', 'Thrash Metal', 'Power Metal', 'Death Metal',
        'Black Metal', 'Folk Metal', 'Symphonic Metal', 'Gothic Metal', 'Glam Metal',
        'Doom Metal', 'Groove Metal', 'Industrial Metal', 'Progressive Metal', 'Nu Metal',
        'Metalcore', 'Deathcore', 'Post Hardcore', 'Grindcore', 'Djent', 'Sludge Metal'
    ],
    'New Age' => ['Ambient', 'Healing', 'Meditation', 'Nature', 'Relaxation'],
    'Opera' => [],
    'Pop' => [
        'Adult Contemporary', 'Baroque Pop', 'Britpop', 'Bubblegum Pop', 'Chamber Pop',
        'Chanson', 'Christian Pop', 'Dance Pop', 'Dream Pop', 'Electro Pop', 'Jangle Pop',
        'New Romanticism', 'Orchestral Pop', 'Pop Rap', 'Pop Rock', 'Pop Punk', 'Power Pop',
        'Psychedelic Pop', 'Soft Rock', 'Synthpop', 'Teen Pop', 'Traditional Pop'
    ],
    'R&B' => [
        'Contemporary R&B', 'Disco', 'Doo Wop', 'Funk', 'Modern Soul', 'Motown', 'Neo-Soul',
        'Northern Soul', 'Quiet Storm', 'Soul', 'Soul Blues', 'Southern Soul'
    ],
    'Reggae' => [
        '2-Tone', 'Dub', 'Roots Reggae', 'Reggae Fusion', 'Lovers Rock', 'Ska', 'Dancehall'
    ],
    'Rock' => [
        'Acid Rock', 'Alternative Rock', 'Arena Rock', 'Art Rock', 'Blues-Rock',
        'British Invasion', 'Glam Rock', 'Grunge', 'Hard Rock', 'Indie Rock', 'Math Rock',
        'Noise Rock', 'Post Punk', 'Post Rock', 'Prog-Rock', 'Psychedelic Rock', 'Punk Rock',
        'Rock & Roll', 'Rockabilly', 'Roots Rock', 'Southern Rock', 'Surf Rock', 'Stoner Rock'
    ],
    'Singer/Songwriter' => [
        'Alternative Folk', 'Contemporary Folk', 'Contemporary Singer/Songwriter',
        'Indie Folk', 'Folk-Rock', 'New Acoustic', 'Traditional Folk'
    ],
    'Soundtrack' => [
        'Foreign Cinema', 'Movie Soundtrack', 'Musicals', 'Original Score',
        'TV Soundtrack', 'Video Game Soundtrack'
    ],
    'Spoken Word' => [],
    'Vocal' => [
        'A Cappella', 'Barbershop', 'Doo-wop', 'Gregorian Chant', 'Standards',
        'Traditional Pop', 'Vocal Jazz', 'Vocal Pop'
    ],
    'World' => [
        'African', 'Afro-Beat', 'Afro-Pop', 'Benga', 'Highlife', 'Celtic', 'Caribbean',
        'Calypso', 'Dancehall', 'Klezmer', 'Middle Eastern', 'Polka', 'Worldbeat', 'Zydeco'
    ]
];

$insertMain = $db->prepare("INSERT INTO genres (name, parent_id) VALUES (?, NULL)");
$insertSub  = $db->prepare("INSERT INTO genres (name, parent_id) VALUES (?, ?)");

$totalMain = 0;
$totalSub  = 0;

foreach ($genres as $mainGenre => $subGenres) {
    $insertMain->execute([$mainGenre]);
    $mainId = $db->lastInsertId();
    $totalMain++;

    foreach ($subGenres as $sub) {
        $insertSub->execute([$sub, $mainId]);
        $totalSub++;
    }
}

echo "Done! Inserted $totalMain genres and $totalSub sub-genres (total: " . ($totalMain + $totalSub) . ").\n";
echo "DELETE THIS FILE: import_genres.php\n";

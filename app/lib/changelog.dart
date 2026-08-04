/// Historique des versions, affiché dans Paramètres → Historique des versions.
/// Ajouter une entrée en tête à chaque nouvelle version livrée.
class ReleaseNote {
  const ReleaseNote(this.version, this.notes);

  final String version;
  final List<String> notes;
}

const kChangelog = <ReleaseNote>[
  ReleaseNote('2.75.0', [
    'La bibliothèque a un nouvel onglet « Genres » : tous les genres en '
        'grille, chacun avec une mosaïque de quatre pochettes, son nombre '
        'd\'artistes et d\'albums, le filtre instantané et la barre A-Z '
        'comme pour les artistes et les albums',
    'Un genre s\'ouvre maintenant sur sa propre page : lecture aléatoire du '
        'genre en un geste, puis tous ses albums en grille et tous ses '
        'artistes en liste',
    'Le bouton « Gérer » (renommer, supprimer un genre) est à portée de main '
        'depuis le nouvel onglet',
  ]),
  ReleaseNote('2.74.0', [
    'Nouvel écran « Infos du serveur » (Paramètres → Compte) : l\'espace '
        'disque restant s\'affiche en gros, avec une jauge qui passe à '
        'l\'orange puis au rouge quand le disque se remplit',
    'On y voit aussi ce qui occupe la place — le poids de la musique et celui '
        'des données (cache, journaux) — ainsi que la taille de la '
        'bibliothèque : titres, albums, artistes, genres, durée cumulée, '
        'taille de la base et date du dernier scan',
    'Et de quoi savoir sur quoi tourne le serveur : système, serveur web, '
        'version de PHP, processeurs, charge, mémoire libre, temps de marche '
        'et heure du serveur',
    'La mesure du poids des dossiers est mise en cache côté serveur : la page '
        's\'ouvre vite même avec des dizaines de milliers de fichiers',
  ]),
  ReleaseNote('2.73.0', [
    'Parties à plusieurs : les invités peuvent enfin écrire leur prénom. Leur '
        'page se rafraîchissait toutes les secondes en refaisant la carte à '
        'neuf — le champ était détruit et recréé, si bien que le clavier se '
        'refermait dès qu\'on touchait la case',
    'La page ne se reconstruit plus que lorsqu\'il se passe vraiment quelque '
        'chose : l\'arrivée des autres joueurs et le compteur du salon se '
        'mettent à jour sur place, sans rien effacer. Et si une '
        'reconstruction s\'impose, la saisie en cours garde son curseur',
  ]),
  ReleaseNote('2.72.0', [
    'Le Défricheur juge maintenant des CHANSONS, pas des albums entiers : '
        'chaque carte est un titre que tu n\'as jamais joué, avec sa pochette, '
        'son album et son année — et toujours trente secondes pour te '
        'décider',
    'Ce que tu gardes rejoint la playlist « Défricheur » titre par titre : '
        'plus d\'album complet ajouté pour une seule chanson qui t\'a plu',
    'Le vivier s\'ouvre du même coup : un album déjà entamé garde ses titres '
        'jamais écoutés à défricher, alors qu\'il disparaissait entièrement '
        'avant. Les extraits trop courts (jingles, interludes) sont écartés',
    'La mémoire du jeu repart à zéro — elle retenait des albums, elle retient '
        'désormais des titres',
  ]),
  ReleaseNote('2.71.0', [
    'La « bande vide » en bas de l\'écran, revenue malgré le correctif de la '
        '2.65.0 : l\'app ne se contente plus de demander la fermeture du '
        'clavier — quand la place reste réservée sans clavier à l\'écran, elle '
        'la reprend d\'elle-même. Le contenu retrouve aussitôt toute la '
        'hauteur',
    'Un champ de saisie resté sélectionné dans un onglet qu\'on a quitté (ou '
        'sur un écran recouvert) ne réserve plus la place de son clavier : '
        'l\'app fait désormais la différence entre un champ à l\'écran et un '
        'champ qui n\'y est plus',
  ]),
  ReleaseNote('2.70.0', [
    'Nouveau jeu, « Défricheur » : l\'app vous sert trente secondes d\'un '
        'album de votre bibliothèque dont vous n\'avez jamais écouté le '
        'moindre titre. Glissez la carte à droite pour garder, à gauche pour '
        'passer (les deux boutons font la même chose)',
    'Tout album gardé rejoint la playlist « Défricheur », en entier — elle se '
        'remplit tournée après tournée, et c\'est elle qu\'on écoute ensuite '
        'pour de bon',
    'Un album déjà jugé ne revient plus, même s\'il n\'a toujours pas été '
        'écouté. Quand il n\'y a plus rien à défricher, un bouton permet de '
        'tout remettre à zéro',
    'Dix albums par tournée, et le vivier choisi dans l\'onglet « Jeux » '
        's\'applique aussi (un genre, une playlist, les favoris)',
  ]),
  ReleaseNote('2.69.0', [
    'Les jeux ne piochent plus forcément dans toute la bibliothèque : on '
        'choisit désormais le vivier depuis l\'onglet « Jeux » — tout, un ou '
        'plusieurs genres, une ou plusieurs playlists, ou les favoris',
    'Le réglage vaut pour les quatre jeux et se garde d\'une partie à '
        'l\'autre. En cours de partie, le bouton en haut de l\'écran permet '
        'd\'en changer : la partie repart aussitôt sur la nouvelle matière',
    'Les parties à plusieurs suivent le même réglage : les manches sont '
        'tirées du vivier choisi par l\'hôte au moment de créer le salon',
    'Quand le vivier retenu ne suffit pas à un jeu, l\'écran le dit '
        'clairement au lieu de laisser croire que la bibliothèque est vide',
  ]),
  ReleaseNote('2.68.0', [
    'On peut se parler pendant une partie à plusieurs : une barre « talkie-'
        'walkie » apparaît en bas de l\'écran. Maintenez le bouton, parlez, '
        'relâchez — votre message part et les autres joueurs l\'entendent '
        'aussitôt, où qu\'ils soient',
    'Les invités ont le même bouton dans leur navigateur : aucun compte ni '
        'installation, juste l\'autorisation du micro demandée au premier '
        'appui. Chacun peut couper les voix de son côté avec l\'icône '
        'haut-parleur',
    'L\'extrait de la manche se met tout seul en sourdine pendant qu\'on parle '
        'ou qu\'on écoute quelqu\'un : la voix passe devant la musique. Les '
        'messages s\'enchaînent dans l\'ordre où ils ont été dits',
    'Un message dure quinze secondes au plus, n\'est écoutable qu\'une minute '
        'et demie, et disparaît du serveur avec la partie — rien n\'est '
        'conservé après le salon',
  ]),
  ReleaseNote('2.67.0', [
    'Les quatre jeux se jouent maintenant à plusieurs. Depuis l\'onglet '
        '« Jeux », créez un salon : Gullify génère un code court et un lien '
        '(gullify.app/j/XXXX) que vous envoyez par SMS. Vos invités l\'ouvrent '
        'dans leur navigateur, donnent leur prénom et jouent — sans compte, '
        'sans rien installer',
    'Deux façons d\'écouter, au choix à la création : « ensemble » (les '
        'extraits ne sortent que de votre appareil, les invités ne font que '
        'répondre) ou « chacun sur son appareil », pour jouer à distance — '
        'chaque invité reçoit alors l\'extrait dans son navigateur',
    'Le serveur mène la partie : c\'est lui qui tire les manches, tient le '
        'chrono et compte les points, identiquement pour tout le monde. '
        'Personne ne reçoit la bonne réponse avant la révélation, et les '
        'points du blind test, de la pochette mystère et du duel récompensent '
        'la rapidité',
    'Chrono à plusieurs : chacun sa frise et ses trois vies, chacun son tour, '
        'et la partie s\'arrête dès qu\'un joueur place sa dixième carte',
    'Le lien meurt avec la partie : dès que vous la fermez il ne répond plus, '
        'et un salon oublié est supprimé au bout de six heures',
  ]),
  ReleaseNote('2.66.0', [
    'Nouvel onglet « Vidéos » dans la barre du bas : cherchez des clips, des '
        'concerts et des lives sur YouTube et regardez-les directement dans '
        'l\'app. Le serveur relaie le flux (les liens YouTube ne sont valables '
        'que depuis la machine qui les demande)',
    'Chaque vidéo peut être gardée sur le serveur : le téléchargement se fait '
        'en pleine qualité (jusqu\'en 1080p, image et son fusionnés) et la '
        'vidéo se relit ensuite depuis le serveur, sans repasser par YouTube. '
        'La progression du téléchargement s\'affiche dans la liste',
    'Lecteur vidéo plein écran : commandes qui s\'effacent, barre de '
        'progression, bascule en mode paysage et écran maintenu allumé. La '
        'musique en cours se met en pause à l\'ouverture d\'une vidéo',
  ]),
  ReleaseNote('2.65.0', [
    'Correction du bug de la « bande vide » en bas de l\'écran : l\'espace du '
        'clavier restait parfois réservé alors que le clavier avait disparu — '
        'plus rien ne s\'affichait dans cette zone, seule la barre du bas '
        'paraissait normale. L\'app referme maintenant le clavier quand on '
        'change d\'onglet ou d\'écran, et rattrape automatiquement l\'espace '
        'resté réservé sans clavier',
    'Recherche et filtres de la bibliothèque : faire défiler la liste referme '
        'le clavier, qui masquait la moitié des résultats',
  ]),
  ReleaseNote('2.64.0', [
    'Compilations (Various Artists) : le lecteur affiche enfin l\'interprète '
        'de la chanson en cours — dans le mini-lecteur, l\'écran de lecture, '
        'la notification et Android Auto — au lieu de « Various Artists ». '
        'Vaut aussi pour les titres joués depuis les favoris, une playlist, '
        'la recherche, les populaires ou la lecture aléatoire',
    'Recherche : les titres de compilations se trouvent maintenant par le '
        'nom de leur interprète',
    'Page album : les rangées de titres sont plus compactes (l\'artiste '
        'n\'est plus répété sous chaque piste, l\'entête le donne déjà)',
  ]),
  ReleaseNote('2.63.0', [
    'Nouvel onglet « Jeux » dans la barre du bas : quatre jeux musicaux qui '
        'se jouent entièrement avec votre propre bibliothèque. Les règles et '
        'le but s\'affichent à la première ouverture de chaque jeu, puis ne '
        'reviennent plus (le bouton « ? » en haut les rappelle à tout moment). '
        'Chaque jeu garde votre meilleur score',
    '« Chrono » : le principe de Hitster, en solo. Un extrait mystère est '
        'joué — aucun titre, aucune pochette — et il faut le glisser au bon '
        'endroit de votre frise chronologique. Bien placé, il rejoint la '
        'frise ; mal placé, vous perdez une vie sur trois',
    '« Blind test » : dix extraits, quatre réponses, quinze secondes par '
        'manche. Plus vous répondez vite, plus vous marquez',
    '« Pochette mystère » : une pochette très floue se précise seconde après '
        'seconde, à vous de reconnaître l\'album le plus tôt possible',
    '« Duel d\'années » : deux albums s\'affrontent, désignez le plus ancien '
        'et enchaînez la plus longue série possible',
    'Les extraits des jeux sont joués à part, sans notification ni '
        'mini-lecteur, pour ne jamais dévoiler la réponse — et la lecture en '
        'cours se met en pause quand une partie commence',
  ]),
  ReleaseNote('2.62.0', [
    'Les paroles reviennent : depuis quelques temps, plus aucune chanson ne '
        'trouvait ses paroles. En cause, une panne du service LRClib.net '
        '(utilisé jusque-là) qui ne répondait plus, et la source de secours '
        'Musixmatch était elle aussi hors service. Gullify va désormais aussi '
        'chercher les paroles sur YouTube Music quand LRClib ne répond pas — '
        'souvent avec la synchronisation ligne par ligne en prime. Aucune '
        'action de votre part : les paroles réapparaissent automatiquement',
  ]),
  ReleaseNote('2.61.0', [
    'Android Auto : les pochettes d\'album qui s\'affichaient toutes petites, '
        'entourées de bandes noires, remplissent maintenant correctement leur '
        'tuile. En cause : beaucoup de jaquettes récupérées sur le web sont des '
        'vignettes non carrées (format 16:9). L\'app les recadrait déjà en carré '
        'à l\'écran, mais Android Auto affichait l\'image brute. Le serveur '
        'fournit désormais une version carrée recadrée (centrée) pour Android '
        'Auto et la notification système, sans changer l\'affichage dans l\'app',
  ]),
  ReleaseNote('2.60.0', [
    'La musique ne cale plus toute seule quand l\'écran est éteint : Gullify '
        'maintient désormais actifs le Wi-Fi et le processeur pendant la '
        'lecture (comme le font Spotify ou YouTube Music). Sans cela, la radio '
        'Wi-Fi se mettait en veille écran éteint et le flux se figeait en '
        '« mise en tampon » au bout de quelques minutes, pour ne repartir '
        'qu\'au réveil du téléphone. Ces protections ne sont tenues que pendant '
        'la lecture et relâchées dès la pause pour préserver la batterie',
  ]),
  ReleaseNote('2.59.0', [
    'Diagnostic de lecture enrichi : un en-tête « État actuel » montre en '
        'direct ce que fait le lecteur (lecture ou pause, piste, position et '
        'tampon) — le journal, lui, ne notait que les changements. L\'app note '
        'aussi désormais un « démarrage de l\'app », signe qu\'Android l\'a '
        'tuée puis relancée en veille (la cause n°1 des arrêts écran éteint), '
        'affiche le titre de la piste sur chaque pause / reprise, et n\'inonde '
        'plus le journal des passages « inactif / masqué » sans intérêt',
  ]),
  ReleaseNote('2.58.0', [
    'Nouveau « Diagnostic de lecture » dans Paramètres → Développement : un '
        'journal consultable directement dans l\'app qui note tout ce qui '
        'touche la lecture — pauses, coupures de flux, interruptions audio, '
        'mises en tampon réseau et passages en veille. Quand la musique '
        's\'arrête toute seule écran éteint, ouvre cet écran, copie les '
        'dernières lignes et envoie-les : on pourra enfin voir ce qui s\'est '
        'passé juste avant',
  ]),
  ReleaseNote('2.57.0', [
    'Android Auto : quand la voiture perd le signal et affiche « Aucun '
        'élément », l\'app réessaie maintenant toute seule en arrière-plan et '
        'recharge la catégorie dès que le réseau revient — plus besoin de '
        'ressortir et rentrer dans le menu',
  ]),
  ReleaseNote('2.56.0', [
    'Apparence : quatre nouvelles couleurs d\'accent à choisir dans les '
        'Paramètres — Turquoise, Fuchsia, Rubis et Graphite — en plus des '
        'teintes existantes, et les pastilles sont réordonnées en un dégradé '
        'plus naturel',
  ]),
  ReleaseNote('2.55.0', [
    'Pré-écoute YouTube Music : l\'écran ne s\'éteint plus pendant qu\'un '
        'extrait joue, donc la lecture ne se coupe plus quand le téléphone '
        'tombait en veille — l\'appareil se remet en veille normalement dès '
        'que tu mets en pause ou que tu arrêtes la pré-écoute',
  ]),
  ReleaseNote('2.54.0', [
    'Recherche YouTube Music : tu peux maintenant écouter un extrait d\'un '
        'titre avant de le télécharger — touche la pochette (ou la ligne) '
        'pour lancer la pré-écoute, une barre de progression apparaît et le '
        'bouton de téléchargement reste à droite',
  ]),
  ReleaseNote('2.53.0', [
    'Recherche YouTube Music : quand tu touches un artiste, l\'app affiche '
        'maintenant sa vraie discographie (ses propres albums) au lieu d\'une '
        'simple recherche d\'albums par nom qui mélangeait d\'autres artistes',
    'Android Auto : plusieurs jaquettes d\'album floues ou manquantes ont été '
        'récupérées en haute définition (1000×1000) côté serveur',
  ]),
  ReleaseNote('2.52.0', [
    'Recherche YouTube Music : les artistes apparaissent maintenant dans les '
        'résultats, en plus des titres et des albums. Touche un artiste pour '
        'voir sa discographie et télécharger ses albums',
  ]),
  ReleaseNote('2.51.0', [
    'Recherche : un bouton « Charger plus » apparaît maintenant aussi bien '
        'dans ta bibliothèque que sur YouTube Music quand il reste des '
        'résultats à afficher',
    'Recherche : en mode « Tout », les résultats sont désormais séparés en '
        'sections « Artistes », « Albums » et « Titres » pour t\'y retrouver '
        'plus facilement',
  ]),
  ReleaseNote('2.50.0', [
    'Ajouter de la musique : tu peux maintenant coller un lien YouTube '
        '(vidéo, album ou playlist) directement dans la recherche pour le '
        'télécharger — pratique quand le bon groupe n\'apparaît pas dans les '
        'résultats',
    'Recherche d\'albums : un bouton « Charger plus » affiche davantage de '
        'résultats au lieu de se limiter aux 10 premiers',
  ]),
  ReleaseNote('2.49.0', [
    'Accueil : nouvelle carte « À découvrir » qui te propose un artiste que '
        'tu n\'as pas encore, choisi parmi les artistes similaires suggérés '
        'par YouTube Music à partir d\'un artiste de ta bibliothèque — avec '
        'le « parce que tu as … dans ta bibliothèque ». Touche la carte pour '
        'l\'explorer, ou le bouton pour une autre suggestion',
  ]),
  ReleaseNote('2.48.0', [
    'Notification de lecture et Android Auto : le bouton stop (carré) en bas '
        'à droite est remplacé par un cœur pour ajouter ou retirer la piste '
        'de tes favoris d\'un seul geste ; l\'icône se remplit quand le titre '
        'est en favori',
  ]),
  ReleaseNote('2.47.0', [
    'Android Auto : les pochettes d\'albums et les images d\'artiste '
        's\'affichent sur les listes d\'albums et d\'artistes ; les longues '
        'listes de pistes (album, playlist, favoris, populaires) restent '
        'légères, sans recharger une pochette par titre',
  ]),
  ReleaseNote('2.46.0', [
    'Paramètres → Bibliothèque : « Gérer les genres » (renommer/supprimer) et '
        '« Scanner la bibliothèque » sont désormais accessibles depuis les '
        'réglages',
    'Scan : lance un scan complet ou rapide du serveur pour détecter les '
        'nouveaux titres, et une détection automatique des genres manquants, '
        'avec suivi de l\'avancement',
  ]),
  ReleaseNote('2.45.0', [
    'Découverte : dans Recherche, une section « Autres utilisateurs » '
        'permet d\'explorer et d\'écouter les bibliothèques des autres '
        'comptes du serveur',
    'Photo de profil : dans Paramètres → Compte, choisis (ou supprime) ta '
        'photo ; elle s\'affiche dans la découverte',
  ]),
  ReleaseNote('2.44.0', [
    'Compilations (Various Artists) : chaque piste affiche « Interprète — '
        'Titre » (lu depuis les tags), au lieu du seul titre',
  ]),
  ReleaseNote('2.43.0', [
    'Correctif : les statistiques comptent TES écoutes (les écoutes d\'un '
        'autre utilisateur sur ta bibliothèque ne s\'y ajoutent plus)',
    'Correctif : logo de connexion propre (mascotte détourée sans trous)',
    'Correctif : télécharger une compilation n\'inonde plus les Nouveautés '
        'de vieux albums (dates réelles préservées)',
  ]),
  ReleaseNote('2.42.0', [
    'Idées : bouton crayon pour modifier le texte d\'une idée existante',
  ]),
  ReleaseNote('2.41.0', [
    'Idées : bouton « Confier à Claude » — Claude réalise l\'idée sur le '
        'serveur et la coche une fois faite (à activer côté serveur)',
  ]),
  ReleaseNote('2.40.0', [
    'Android Auto : menu calqué sur l\'app mobile — Accueil (Aléatoire, '
        'Découverte, Nouveautés, Populaires, Derniers joués), Bibliothèque '
        '(Artistes, Albums, Favoris, Playlists, Genres), Radios, Favoris',
    'Correctif : la réinitialisation des statistiques rafraîchit bien les '
        'chiffres à l\'écran',
    'Mascotte Gullify sur les écrans de connexion',
  ]),
  ReleaseNote('2.39.0', [
    'Statistiques : graphiques repensés (barres en dégradé sur piste douce, '
        'plus lisibles et cohérents avec le style)',
  ]),
  ReleaseNote('2.38.0', [
    'Statistiques : les « Top titres » reflètent enfin tes écoutes réelles '
        '(fini les titres jamais joués en tête)',
    'Bouton de réinitialisation des statistiques',
  ]),
  ReleaseNote('2.37.0', [
    'Android Auto : bouton de recherche (vocal + clavier) avec résultats',
    'Android Auto : menu réordonné + Playlists, et « Tout lire / aléatoire » '
        'sur Nouveautés et sur toute la bibliothèque',
  ]),
  ReleaseNote('2.36.0', [
    'Icône d\'app : mascotte encore agrandie pour bien couvrir la tuile '
        '(headroom réduit)',
  ]),
  ReleaseNote('2.34.0', [
    'Android Auto : initialisation blindée (le menu ne peut plus rester '
        'vide au démarrage voiture) + journal de diagnostic dans l\'app '
        '(Paramètres → Diagnostic Android Auto)',
  ]),
  ReleaseNote('2.33.0', [
    'Android Auto : si la recherche vocale ne trouve rien en local, repli '
        'YouTube — télécharge puis joue',
    'Le genre s\'affiche sur la page de l\'artiste',
  ]),
  ReleaseNote('2.32.0', [
    'Correctif : les menus (feuilles) s\'affichent au-dessus du dock et du '
        'mini-lecteur, plus derrière',
    'Messages (SnackBars) flottants au-dessus de la barre',
  ]),
  ReleaseNote('2.31.0', [
    'Accueil : bouton « Aléatoire » (toute la bibliothèque)',
    'Accueil : bouton « Découverte » (titres jamais joués)',
  ]),
  ReleaseNote('2.30.0', [
    'Attribution du genre avec autocomplétion sur tous les genres',
    'Écran de gestion des genres : renommer ou supprimer (Bibliothèque → '
        'Artistes → Gérer)',
  ]),
  ReleaseNote('2.29.0', [
    'Carnet d\'idées directement dans l\'app (Paramètres → Mes idées)',
    'Synchronisé côté serveur : notées sur mobile, lues par Claude',
  ]),
  ReleaseNote('2.28.0', [
    'Historique des versions dans les Paramètres',
    'Carnet d\'idées de développement (IDEAS.md)',
  ]),
  ReleaseNote('2.27.0', [
    'Onglet Radio : recherche par nom et filtre par genre',
  ]),
  ReleaseNote('2.26.0', [
    'Artistes similaires via YouTube Music sur la page artiste',
  ]),
  ReleaseNote('2.25.0', [
    'Définir le genre d\'un artiste (avec suggestions)',
    'Filtre par genre dans la bibliothèque',
  ]),
  ReleaseNote('2.24.0', [
    'Suppression définitive d\'une piste, d\'un album ou d\'un artiste',
  ]),
  ReleaseNote('2.23.0', [
    'Gestion des web radios : ajout, édition, suppression',
    'Icône de radio par URL ou fichier local; sélection multiple',
  ]),
  ReleaseNote('2.22.0', [
    'Correctif : le téléchargement d\'un album YouTube ne fait plus tout '
        'disparaître',
    'Recherche filtrable par source (bibliothèque / YouTube) et par type',
  ]),
  ReleaseNote('2.21.0', [
    'Listes de titres plus aérées et uniformes; menu par appui long partout',
    'Barre de navigation présente en permanence',
    'Correctif : la bibliothèque affiche enfin tous les albums',
  ]),
  ReleaseNote('2.20.0', [
    'En-têtes artiste et album fondus dans le décor',
    'Listes de titres avec séparateurs et surlignage de la piste en cours',
  ]),
  ReleaseNote('2.19.0', [
    'Nouvelle navigation : dock avec orbe d\'accueil central',
    'Favoris devient un onglet',
  ]),
  ReleaseNote('2.18.0', [
    'Thèmes : une structure de verre + choix de couleur d\'accent et de '
        'base claire/sombre',
  ]),
  ReleaseNote('2.15.0', [
    'Police du design (Hanken Grotesk) et mascotte Gullify',
  ]),
  ReleaseNote('2.14.0', [
    'Retour aux 4 onglets, installeur de mise à jour natif',
    'Correctif du lecteur en plein écran sur les pages de détail',
  ]),
];

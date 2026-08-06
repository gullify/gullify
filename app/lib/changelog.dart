/// Historique des versions, affiché dans Paramètres → Historique des versions.
/// Ajouter une entrée en tête à chaque nouvelle version livrée.
class ReleaseNote {
  const ReleaseNote(this.version, this.notes);

  final String version;
  final List<String> notes;
}

const kChangelog = <ReleaseNote>[
  ReleaseNote('2.94.0', [
    'Un bouton « micro barré » s\'ajoute en haut des paroles : il passe le '
        'titre en cours en version karaoké, voix atténuée, sans perdre une '
        'seconde de lecture — même file, même piste, même endroit. Rebasculer '
        'le bouton rend la voix',
    'Comment ça marche, et ce que ça vaut : il n\'existe aucune API de '
        'versions karaoké, et une vraie séparation des pistes demanderait un '
        'modèle de plusieurs gigaoctets. Le serveur fait donc l\'autre chose '
        'que la technique sait faire vite et bien : il annule le centre du '
        'mixage, là où la voix lead se trouve presque toujours, en gardant '
        'les graves. Ce n\'est pas un instrumental de studio — les chœurs '
        'centrés et une partie de la caisse claire partent avec la voix — '
        'mais c\'est de quoi chanter dessus',
    'Le rendu se fait une fois par titre, en quelques secondes, et le serveur '
        'le garde. Le bouton attend qu\'il soit prêt avant de basculer, et '
        'prépare d\'avance le titre suivant pour que le mode tienne d\'un '
        'morceau à l\'autre. Un titre mixé trop au centre (vieux '
        'enregistrements, mono) est refusé en disant pourquoi : il n\'y a '
        'rien à retirer sans effacer le reste',
    'Un titre téléchargé continue de jouer depuis le téléphone quand une file '
        'se construit : le karaoké vit sur le serveur, il ne doit jamais '
        'ramener la voiture sans réseau vers le réseau',
  ]),
  ReleaseNote('2.93.0', [
    'Dans le lecteur, le nom de l\'album (en haut) et celui de l\'artiste '
        '(sous le titre) mènent maintenant à leur page : un petit chevron '
        'indique qu\'on peut y aller, et le lecteur se referme en passant la '
        'main — on revient donc de l\'artiste à la page d\'où l\'on écoutait, '
        'mini-lecteur toujours là, plutôt que de rouvrir le plein écran',
    'Si le lecteur avait justement été ouvert depuis cet album (ou cet '
        'artiste), il se contente de se refermer : plus de doublons empilés '
        'derrière le bouton retour. Les titres sans album ni artiste connus '
        '(radio, pré-écoute YouTube) gardent un texte simple',
  ]),
  ReleaseNote('2.92.0', [
    'La page des accords a maintenant son accordeur : le bouton en forme de '
        'cadran, à côté des boutons de transposition, ouvre un accordeur qui '
        'écoute la guitare au micro. La note entendue s\'affiche en grand, '
        'l\'aiguille dit de combien on est trop grave ou trop aigu, et la '
        'corde visée s\'allume — verte quand elle est juste',
    'L\'accordeur part sur l\'accordage annoncé par la grille du titre '
        '(Drop D, demi-ton plus bas…) et huit accordages sont proposés, du '
        'standard au DADGAD. La musique se met en pause le temps d\'accorder '
        '— sans quoi le micro entendrait le haut-parleur avant la corde — et '
        'repart à la fermeture, l\'écran restant allumé pendant ce temps',
  ]),
  ReleaseNote('2.91.0', [
    'Un bouton guitare rejoint les paroles dans le lecteur : il ouvre la '
        'grille d\'accords du titre en cours, accords en couleur au-dessus '
        'des paroles, avec le capo, la tonalité et l\'accordage annoncés en '
        'haut. Les grilles viennent d\'Ultimate-Guitar, et le serveur garde '
        'celles qu\'il a déjà trouvées',
    'Chaque accord de la grille est dessiné : un petit manche avec les cases, '
        'les cordes à vide et les cordes étouffées, pour ne pas avoir à '
        'chercher le doigté ailleurs',
    'Deux boutons pour jouer avec : « + » et « − » transposent toute la '
        'grille sans décaler les accords au-dessus des syllabes, et le '
        'défilement automatique — quatre vitesses — fait avancer la page '
        'pendant qu\'on a les deux mains sur la guitare. Si aucune grille '
        'n\'existe, l\'app propose d\'aller chercher soi-même',
  ]),
  ReleaseNote('2.90.0', [
    'Android Auto sans réseau ne reste plus sur « Aucune sélection ». La '
        'vraie raison : au démarrage dans la voiture, l\'app demandait au '
        'serveur de confirmer la session; sans réseau elle la jetait, et la '
        'bibliothèque n\'avait plus rien à répondre — même une fois le signal '
        'revenu. Le jeton est maintenant gardé : les listes se remplissent '
        'toutes seules dès que le serveur répond de nouveau',
    'À la place d\'un écran vide, chaque liste qui n\'a pas pu se charger '
        'propose « Réessayer » et affiche les titres téléchargés sur le '
        'téléphone, jouables sans réseau. Le réessai automatique, lui, ne '
        'baisse plus les bras au bout de deux minutes : il attend le retour du '
        'signal aussi longtemps qu\'il faut, et recharge l\'écran de la voiture '
        'sans qu\'on ait à y toucher',
    'Nouvelle entrée « Téléchargements » dans la Bibliothèque d\'Android '
        'Auto : tout lire, en aléatoire ou un titre précis, sans la moindre '
        'connexion. La recherche, vocale ou au clavier, y pioche aussi quand '
        'le serveur est injoignable',
  ]),
  ReleaseNote('2.89.0', [
    'Écouter un titre trouvé dans la recherche YouTube, c\'est maintenant le '
        'lecteur de Gullify qui le fait. Cette pré-écoute avait le sien, à '
        'l\'écart : le lecteur ne s\'ouvrait pas, la notification ne disait '
        'rien, et l\'écran éteint coupait le son au bout de quelques secondes. '
        'Elle part désormais comme une chanson — mini-lecteur, écran '
        'verrouillé, veille — et remplace la file d\'attente, comme une radio',
    'Du coup, plus jamais deux sons à la fois. Une pré-écoute lancée puis un '
        'medley de genre ouvert dans la foulée jouaient l\'un par-dessus '
        'l\'autre : chacun ne faisait taire que le lecteur principal, qui ne '
        'jouait pas. Le medley coupe maintenant la pré-écoute, et la '
        'pré-écoute coupe le medley',
    'Le medley de genre, lui, garde son lecteur à part et s\'arrête toujours '
        'à la fermeture du dialogue : il croise deux extraits à la fois pour '
        'ses fondus, ce qu\'un lecteur unique ne sait pas faire, et il ne doit '
        'pas jeter la file d\'attente en cours à chaque artiste rangé. Il sert '
        'à choisir un genre, pas à écouter',
  ]),
  ReleaseNote('2.88.0', [
    'Les lecteurs de Gullify ne sont plus « chacun le sien ». La version '
        'précédente leur donnait le même réglage, mais chacun gardait le sien '
        'allumé dans son coin pour la vie de l\'app. Ils se passent maintenant '
        'les mêmes : la pré-écoute YouTube, le medley de genre, les extraits '
        'des manches et les messages vocaux des parties en empruntent un le '
        'temps de faire du son, et le rendent en se taisant. Le medley qui '
        's\'arrête laisse ses deux lecteurs à la manche de jeu suivante, qui les '
        'reprend tels quels',
    'Au repos, l\'app n\'en garde donc plus un seul allumé — un lecteur qui ne '
        'joue pas tient quand même un décodeur du téléphone, et il y en avait '
        'jusqu\'à cinq. Un lecteur rendu est arrêté et remis à plein volume '
        'avant d\'être reprêté : un fondu de medley ne peut plus laisser la '
        'manche suivante muette',
    'Le lecteur principal, lui, reste à part : c\'est le seul qui tient la file '
        'd\'attente et la notification, et le seul qu\'on ne prête à personne',
  ]),
  ReleaseNote('2.87.0', [
    'Tous les lecteurs de Gullify sortent maintenant du même moule. La '
        'pré-écoute YouTube, le medley de genre, les extraits des jeux et les '
        'messages vocaux des parties gardaient chacun un lecteur brut, sans '
        'rien du réglage patiemment mis au point pour le lecteur principal. Ils '
        'tiennent désormais eux aussi le verrou qui garde la Wi-Fi et le '
        'processeur actifs pendant la lecture — c\'est ce qui évitait déjà les '
        '« mise en tampon » écran éteint',
    'Et les extraits partent plus vite. Un medley ou une manche de jeu n\'a pas '
        'besoin du même tampon qu\'un morceau écouté d\'un bout à l\'autre : on '
        'télécharge moins d\'avance pour vingt-six secondes de musique, et la '
        'première note arrive en une seconde et demie au lieu de deux et demie',
  ]),
  ReleaseNote('2.86.0', [
    'Ranger les genres se fait maintenant à la chaîne. Le dialogue offre deux '
        'boutons : « Enregistrer », qui range et referme, et « Enregistrer et '
        'suivant », qui range et rouvre aussitôt le choix sur l\'artiste '
        'suivant sans genre — plus de proposition à attraper au vol avant '
        'qu\'elle ne disparaisse',
    'Et le medley part tout seul à l\'ouverture : entendre l\'artiste est ce '
        'qui aide le plus à le ranger, et le demander à chaque fois faisait un '
        'tap de trop sur une série entière. En enchaînant, il passe à '
        'l\'artiste suivant sans un instant de silence',
  ]),
  ReleaseNote('2.85.0', [
    'Le medley enchaîne enfin ses extraits. Les fondus ne s\'entendaient pas : '
        'ils ne laissaient qu\'un blanc entre chaque titre. Gullify tient '
        'maintenant deux lecteurs, et le titre suivant se charge et démarre '
        'pendant que le précédent joue encore — l\'un monte pendant que '
        'l\'autre descend, sans jamais un instant de silence',
    'Et les extraits durent plus longtemps : vingt-six secondes au lieu de '
        'dix-huit, de quoi reconnaître un titre avant qu\'il ne passe',
  ]),
  ReleaseNote('2.84.0', [
    'La suggestion de genre ne dépend plus de MusicBrainz seul. Quand il ne '
        'dit rien de l\'artiste — ce qui arrivait presque à tout coup sur la '
        'musique d\'ici — Gullify demande à Deezer, qui compte le genre de '
        'chacun de ses albums, puis à Apple Music. Le dialogue dit de quel '
        'catalogue vient la suggestion',
    'Et il ne suggère plus n\'importe quoi : « Anonyme Introuvable XYZ » '
        'ramenait le groupe « XYZ », que MusicBrainz notait pourtant 100. Un '
        'nom court avalé par un nom long n\'est plus le même artiste',
    'Le medley donne toujours cinq extraits. Un artiste d\'un seul album n\'en '
        'avait qu\'un, qui tournait en rond : Gullify va maintenant chercher '
        'plusieurs titres du même disque, étalés du début à la fin',
    'Le choix du genre tient dans l\'écran. Les tuiles, plus petites, sont les '
        'seules à défiler : la suggestion et le medley restent en tête, le '
        'champ « Autre genre » et les boutons sous la main — plus rien n\'est '
        'poussé hors de l\'écran',
  ]),
  ReleaseNote('2.83.0', [
    'On peut enfin ajouter des genres. « Gérer les genres » (Paramètres) a un '
        'bouton « Ajouter » : le genre créé rejoint la liste proposée au '
        'moment de ranger un artiste, et se choisit d\'un tap comme les 21 '
        'autres — plus besoin de le retaper à chaque fois pour ce que la '
        'liste ne couvre pas',
    'Un genre ajouté reste dans la liste même si personne ne le porte encore. '
        'Il apparaît alors avec « Aucun artiste », et se renomme ou se '
        'supprime comme les autres',
  ]),
  ReleaseNote('2.82.0', [
    'Le medley s\'entend enfin. Il avait tout l\'air de tourner — le titre '
        'défilait, les barres bougeaient — mais pas une note n\'en sortait : '
        'Gullify attendait la fin du morceau avant de monter le son, et un '
        'extrait ne finit jamais. Le fondu d\'entrée restait donc à zéro, et '
        'l\'extrait suivant n\'arrivait pas davantage. Les extraits '
        's\'enchaînent maintenant en fondu, d\'un album à l\'autre, comme '
        'promis',
  ]),
  ReleaseNote('2.81.0', [
    'Ranger la bibliothèque se fait maintenant par séries : une fois le genre '
        'd\'un artiste enregistré, Gullify propose d\'enchaîner sur le suivant '
        'qui n\'en a pas. Un tap sur « Ranger » rouvre le choix sur place, '
        'avec sa suggestion et son medley — sans repasser par la '
        'bibliothèque à chaque fois',
    'Le dialogue dit désormais de quel artiste il s\'agit, et quand il ne '
        'reste plus personne à ranger, il le dit aussi',
  ]),
  ReleaseNote('2.80.0', [
    'Choisir le genre d\'un artiste commence par une suggestion : Gullify '
        'demande à MusicBrainz ce qu\'on sait de lui, la ramène à la liste des '
        '21 genres et la propose d\'un tap, en montrant les étiquettes qui '
        'l\'ont dictée. Elle ne décide rien — le choix reste entier, et quand '
        'rien n\'est sûr elle le dit plutôt que de ranger de travers',
    'Le temps de se décider, un medley : quelques extraits pris sur plusieurs '
        'albums de l\'artiste, enchaînés en fondu, en boucle. Il s\'arrête '
        'tout seul en refermant le dialogue, et laisse la lecture en cours '
        'reprendre sa place',
  ]),
  ReleaseNote('2.79.0', [
    'Une idée confiée à Claude prévient quand elle est faite : la cloche de '
        'l\'accueil s\'allume, la notification rappelle l\'idée et la version '
        'qui la livre, et un tap ouvre le carnet d\'idées. Si Claude a préféré '
        'ne pas s\'y risquer, il le dit là aussi plutôt que de laisser l\'idée '
        'traîner sans nouvelle',
    'Les notifications se lisent enfin : cartes de verre, icône et couleur '
        'selon ce qu\'elles annoncent, âge en clair (« il y a 5 min »), et le '
        'compteur de la cloche se met à jour tout seul pendant que l\'app est '
        'ouverte',
  ]),
  ReleaseNote('2.78.0', [
    'Changer le genre d\'un artiste ne finit plus sur un message d\'erreur : '
        'le dialogue se refermait avant que le serveur ait répondu, et '
        'Gullify perdait le fil de ce qu\'il était en train d\'enregistrer. '
        'Le genre est bien enregistré et les listes se rafraîchissent, même '
        'quand le serveur prend son temps',
  ]),
  ReleaseNote('2.77.0', [
    'La musique repart : plus aucune chanson ne démarrait et le lecteur '
        'répondait toujours la même erreur, à cause de l\'égaliseur — il '
        'demandait ses réglages au lecteur avant que celui-ci n\'ait ouvert '
        'sa sortie audio, et l\'échec bloquait tout le reste',
    'L\'égaliseur ne vit plus à l\'intérieur du lecteur : Gullify le branche '
        'lui-même sur le son en cours, une fois la lecture partie. S\'il est '
        'refusé par le téléphone, il le dit — la musique, elle, continue',
    'Sa page marche de nouveau : les bandes de l\'appareil, les presets '
        '(Rock, Jazz, Basses +…) et les réglages retrouvés au lancement. '
        'Avant la première chanson, elle invite simplement à en lancer une, '
        'le temps qu\'Android ouvre la sortie audio',
  ]),
  ReleaseNote('2.76.0', [
    'La bibliothèque se range enfin dans une liste courte de 21 genres '
        'principaux — Chanson québécoise/francophone, Traditionnel québécois, '
        'Acadien, Folk, Country, Pop, Rock, Alternatif / Indie, Punk, Métal, '
        'Hip-hop / Rap, R&B / Soul, Reggae, Jazz, Blues, Électronique, '
        'Classique, Musique du monde, Gospel / Spirituel, Trames sonores et '
        'Musique pour enfants — sans sous-genres',
    'Les 90 étiquettes qui traînaient dans la bibliothèque (« Melodic Death '
        'Metal », « Punk Rock », « Music », « Special Purpose Artist »…) ont '
        'été ramenées à ces genres ; celles qui ne disent rien de la musique '
        'ont été effacées pour laisser la détection refaire le travail',
    'La détection de genre ne retient plus la première étiquette venue : elle '
        'pèse toutes celles de MusicBrainz et garde celle qui range vraiment, '
        'en laissant passer devant les genres d\'ici (« néo-trad » ne se dit '
        'pas par hasard) sans pour autant transformer un groupe punk '
        'québécois en chanson',
    'Elle sait aussi retrouver les artistes dont le nom traîne un préfixe '
        '(« (50 First Dates) Bob Marley »), vérifie que l\'artiste trouvé est '
        'bien le bon, et réessaye quand MusicBrainz refuse une requête au '
        'passage',
    'Le genre d\'un artiste se choisit maintenant d\'un tap dans la liste, au '
        'lieu de se retaper à la main — avec un champ libre pour les cas à '
        'part et un bouton pour le retirer',
  ]),
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

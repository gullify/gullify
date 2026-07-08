/// Historique des versions, affiché dans Paramètres → Historique des versions.
/// Ajouter une entrée en tête à chaque nouvelle version livrée.
class ReleaseNote {
  const ReleaseNote(this.version, this.notes);

  final String version;
  final List<String> notes;
}

const kChangelog = <ReleaseNote>[
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

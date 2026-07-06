/// Historique des versions, affiché dans Paramètres → Historique des versions.
/// Ajouter une entrée en tête à chaque nouvelle version livrée.
class ReleaseNote {
  const ReleaseNote(this.version, this.notes);

  final String version;
  final List<String> notes;
}

const kChangelog = <ReleaseNote>[
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

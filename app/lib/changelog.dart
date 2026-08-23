/// Historique des versions, affiché dans Paramètres → Historique des versions.
/// Ajouter une entrée en tête à chaque nouvelle version livrée.
class ReleaseNote {
  const ReleaseNote(this.version, this.notes);

  final String version;
  final List<String> notes;
}

const kChangelog = <ReleaseNote>[
  ReleaseNote('3.38.0', [
    'Gullify s\'installe maintenant sur Google TV. Le même fichier sert le '
        'téléphone et le téléviseur : l\'app demande à Android sur quoi elle '
        's\'ouvre et bascule toute seule vers une interface prévue pour être '
        'lue à trois mètres et manœuvrée à la croix directionnelle',
    'Six écrans pensés pour le salon : accueil en rangées, bibliothèque en '
        'grille, recherche avec clavier à l\'écran, favoris, radios, et les '
        'jeux à plusieurs. L\'élément visé grossit et s\'auréole d\'indigo — '
        'sur un téléviseur, le focus tient lieu de curseur',
    'L\'écran de lecture prend enfin toute la place : la pochette floutée '
        'occupe le fond, le panneau de verre flotte dessus, et les flèches '
        'gauche et droite avancent de dix secondes quand la barre de '
        'progression est visée',
    'Les jeux à plusieurs trouvent leur écran : la télé affiche le code et '
        'son QR, chacun rejoint depuis son téléphone, et le son sort des '
        'haut-parleurs du salon. Rien à changer côté serveur — la télé est un '
        'joueur hôte de plus',
    'Le rail de navigation ne s\'ouvre qu\'en recevant le focus : le reste du '
        'temps il se réduit à une bande d\'icônes et laisse la place à la '
        'musique',
    'Paramètres → Développement → « Interface téléviseur » permet d\'essayer '
        'cette interface depuis un téléphone, sans attendre d\'être devant '
        'la télé',
  ]),
  ReleaseNote('3.37.0', [
    'Dans Android Auto, un genre se lance mélangé d\'un seul geste : '
        '« Lecture aléatoire — Punk » est la PREMIÈRE entrée du genre, avant '
        'ses artistes. Elle portait jusqu\'ici le même libellé que celle du '
        'cran au-dessus, qui lance toute la bibliothèque ; les deux se '
        'nomment désormais, on ne peut plus les confondre au volant',
    'Un genre reste jouable même quand sa liste d\'artistes ne vient pas. Le '
        'moindre accroc réseau sur cette liste faisait basculer l\'écran '
        'entier sur le repli hors ligne : le genre devenait injouable alors '
        'que le serveur savait très bien quoi jouer. Les deux entrées de '
        'lecture restent en place, avec de quoi réessayer',
    'Et quand le vivier d\'un genre revient vide, on va le chercher artiste '
        'par artiste plutôt que de laisser le silence. Un genre qui ne rend '
        'rien ne laisse plus non plus la voiture sur un chargement sans fin — '
        'c\'était l\'« Impossible de charger votre sélection » qui ne partait '
        'jamais',
  ]),
  ReleaseNote('3.36.0', [
    'Le volume est normalisé : tous les titres jouent au même niveau, quel que '
        'soit celui auquel ils ont été gravés. Le volume d\'un morceau est posé '
        'à sa première note, tenu jusqu\'à la dernière, et le même d\'une '
        'écoute à l\'autre quoi qu\'on ait entendu avant',
    'C\'est le renversement que réclamait l\'augmentation qui restait. Depuis '
        'l\'idée #101, le titre entrant était mis au niveau du SORTANT : une '
        'correction relative, décidée au passage, transmise de titre en titre. '
        'Or un volume ne peut que descendre — au-delà du plein volume, un '
        'lecteur sature. Le premier titre d\'une file joue donc à fond, et la '
        'chaîne n\'a plus qu\'un sens pour se rattraper',
    'Ce que la mesure dit, files de quarante titres tirés au sort dans les 581 '
        'profils de la bibliothèque : la correction butait sur une de ses '
        'bornes 38 % du temps, et chaque fois qu\'elle butait, l\'écart passait '
        'tel quel dans les oreilles. Un passage sur douze faisait entrer le '
        'titre suivant plus de deux décibels au-dessus du précédent, et le '
        'centile 99 montait à ONZE décibels. L\'enflure n\'était pas dans la '
        'forme des rampes : elle était dans le principe',
    'Chaque titre est donc désormais amené sur un niveau de référence FIXE, '
        '−18 dB, le décile inférieur de la bibliothèque : neuf titres sur dix '
        'y arrivent exactement. L\'étalement de ce qu\'on entend (centiles 10 '
        'à 90) tombe de 4,8 décibels à ZÉRO. Deux titres qui se croisent sont '
        'alors déjà à niveau — le passage n\'a plus rien à corriger, et rien ne '
        'vient passer au-dessus de celui qui s\'achève',
    'Ce que ça coûte, dit franchement : l\'ensemble joue 2,3 décibels moins '
        'fort qu\'avant. On ne sait que retenir un morceau, jamais le pousser '
        'sans le faire saturer. Un niveau global plus bas se rattrape une fois '
        'avec le bouton de volume ; un écart entre deux titres se subit à '
        'chaque passage. Le réglage se coupe dans Paramètres → Lecture → Fondu',
    'Et le titre sortant est mis en sourdine AVANT qu\'on arrête son lecteur, '
        'jamais après. Reprendre la main en plein croisement — saut, pause, '
        'arrêt — pouvait lui laisser le temps d\'un éclat à plein volume : une '
        'augmentation de la chanson qui termine, très exactement',
  ]),
  ReleaseNote('3.35.0', [
    'Le lecteur ne touche plus au volume en dehors des transitions. C\'est là '
        'qu\'était l\'augmentation qui restait : pas dans le croisement, mais '
        'dans la remise à niveau qui le suivait. Un titre entrant retenu se '
        'voyait rendre ses décibels par une lente remontée — six secondes '
        'd\'abord, une vingtaine ensuite —, et une dérive de volume sous une '
        'musique installée s\'entend comme quelqu\'un qui monte le son, si '
        'lente soit-elle',
    'La mise à niveau se compare maintenant aux niveaux des MORCEAUX et non à '
        'ceux de leurs bords. Se caler sur la fin du sortant revenait à '
        'prendre son dernier soupir pour sa voix : un titre finit six décibels '
        'et demi sous son propre niveau, si bien qu\'une transition sur trois '
        'réclamait plus de douze décibels de correction. On retenait l\'entrant '
        'du maximum permis — six décibels — sans rien égaler pour autant, et '
        'il fallait bien les lui rendre ensuite',
    'Le volume posé pendant le croisement est désormais celui que le titre '
        'garde jusqu\'à sa dernière note : c\'est le niveau exact de celui '
        'qu\'il remplace, une fois pour toutes. Une pause, une reprise, un '
        'retour de fondu de fin ne l\'effacent plus',
    'Et la correction va dans les deux sens. Elle ne savait que retenir : une '
        'file de morceaux gravés fort ne pouvait que s\'enfoncer. Un morceau '
        'gravé bas fait maintenant remonter le niveau — jamais au-delà du '
        'plein volume, jamais plus de six décibels en dessous',
  ]),
  ReleaseNote('3.34.0', [
    'Le verre d\'Apple arrête d\'en faire trop. La disposition ne bouge pas '
        'd\'un pixel — c\'est la MATIÈRE qui se reprend. La fois d\'avant, '
        'pour répondre à « je ne vois aucune différence », tous les curseurs '
        'étaient montés à fond : un verre poussé à fond ne fait pas plus de '
        'verre, il fait du plastique irisé sur fond de taches grises',
    'Le flou descend de 28 à 10, la fourchette où le moteur travaille. À 28, '
        'le fond derrière une barre n\'était plus qu\'un aplat — et un aplat '
        'plié reste un aplat : la lentille n\'avait plus rien à réfracter et '
        'redevenait le panneau laiteux qu\'on lui reproche depuis le début. On '
        'lit de nouveau ce qui passe dessous, et la lisibilité du texte est '
        'reprise par le voile d\'iOS 26, qui blanchit le verre sans toucher à '
        'l\'encre',
    'Les ombres redeviennent celles d\'Apple : 6 % de noir sur 8 px, au lieu '
        'de 52 px de flou décalés de 22. Chaque vitre traînait un halo gris — '
        'sur le dock, sur les cartes, sous la pochette du lecteur',
    'Les cartes qui défilent ne clignotent plus. Le rendu le plus fin '
        'photographie le fond pour le plier : dans une liste qui bouge, cette '
        'photo montre ce qui était là juste avant. Il reste donc aux surfaces '
        'qui ne défilent pas (barres, lecteur, boutons flottants) ; le reste '
        'passe au rendu prévu pour le mouvement',
    'Et sur les appareils où le shader ne tourne pas, on n\'empile plus deux '
        'vitres l\'une sur l\'autre — c\'est ce qui donnait, là, un panneau '
        'blanc opaque à la place d\'une lentille. Épaisseur, prisme, éclat et '
        'fond d\'écran redescendent eux aussi aux valeurs de la matière',
  ]),
  ReleaseNote('3.33.0', [
    'Le verre d\'Apple se voit enfin. La réfraction livrée la fois d\'avant '
        'tournait bien — mais on la repeignait aussitôt : la vitre dessinée à '
        'la main, son reflet et son éclat d\'angle s\'empilaient à près de '
        'trois quarts de blanc dans le coin haut-gauche, c\'est-à-dire pile là '
        'où le fond se plie et se sépare en couleurs. La peinture s\'efface '
        'donc là où le shader tourne, et lui laisse la place',
    'La vitre est aussi plus épaisse et son prisme plus franc : la bande où le '
        'fond se déforme est maintenant assez large pour se voir sans la '
        'chercher, sur le dock comme sur le mini-lecteur. Là où le shader ne '
        'peut pas tourner, la vitre dessinée se peint en entier, comme avant — '
        'aucune barre ne peut disparaître',
    'Le lecteur plein écran a enfin du verre, lui aussi. Il était le seul '
        'écran à n\'en avoir aucun : des commandes nues posées sur un voile '
        'presque opaque. Le titre et la forme d\'onde se rangent maintenant '
        'sur une vitre, le transport et les actions sur une seconde, la flèche '
        'de fermeture devient un disque de verre, et le voile s\'allège pour '
        'qu\'il reste quelque chose à laisser passer',
    'Au passage, la pochette du lecteur rétrécit au lieu de pousser les '
        'commandes hors de l\'écran sur un petit téléphone',
  ]),
  ReleaseNote('3.32.0', [
    'Le thème Apple Liquid Glass réfracte enfin. C\'était ce qui lui manquait '
        'pour « vraiment » y ressembler : une lentille ne floute pas ce qu\'il '
        'y a derrière elle, elle le PLIE. Le fond se resserre et se décale sur '
        'tout le pourtour des barres, et ses couleurs s\'y séparent comme dans '
        'un prisme — c\'est cette déformation, bien plus que le liseré, qui '
        'fait la différence entre du verre et un rectangle flouté',
    'La déformation se calcule dans un shader, pixel par pixel, à partir du '
        'moteur de rendu liquid_glass_widgets. Sur les appareils où il ne peut '
        'pas tourner, la vitre dessinée d\'avant reprend la main : rien ne '
        'disparaît nulle part',
    'Le flou du thème redescend de 48 à 28. À 48, le fond n\'était plus qu\'une '
        'bouillie de couleurs : la lentille n\'avait plus rien à plier. Le '
        'givre reste plus profond que celui du verre Gullify, mais on '
        'reconnaît de nouveau ce qui passe dessous',
  ]),
  ReleaseNote('3.31.0', [
    'Le son ne remonte plus après un croisement. C\'est là que se cachait ce '
        'qui restait d\'enflure : un morceau finit presque toujours plus bas '
        'qu\'il n\'a joué, donc presque TOUS les passages retenaient le titre '
        'entrant de quelques décibels — et les lui rendaient six secondes plus '
        'tard. Une seconde transition, celle-là bien audible',
    'La remise à niveau prend maintenant tout son temps : un quart de décibel '
        'par seconde, le temps d\'un couplet pour retrouver le plein volume. '
        'À cette vitesse l\'oreille ne suit plus le niveau, elle entend la '
        'musique — et elle avance en décibels plutôt qu\'en amplitude, parce '
        'que c\'est ce que l\'oreille mesure',
    'Deux titres qui s\'enchaînent vite ne s\'empilent plus. Le titre entrant '
        'se cale désormais sur ce que le sortant fait VRAIMENT entendre, et '
        'plus seulement sur le niveau auquel il est gravé : un morceau encore '
        'en train de remonter de son propre croisement joue sous son niveau, '
        'et le suivant arrivait par-dessus',
    'Le medley des genres croisait ses extraits selon la loi qui fait enfler '
        'le passage de deux décibels — celle-là même qu\'on avait corrigée '
        'dans le lecteur. Il suit maintenant la même règle que le fondu '
        'enchaîné : le passage ne sonne ni plus fort ni plus faible que les '
        'extraits qu\'il relie',
  ]),
  ReleaseNote('3.30.0', [
    'Android Auto n\'affiche plus « Impossible de charger votre sélection » '
        'sur l\'écran d\'accueil de la voiture. Android demande au démarrage '
        'une liste à part, celle de la reprise, et y attend UN morceau '
        'jouable : Gullify répondait une liste vide, et c\'était l\'erreur',
    'Il y a maintenant une vignette « reprendre » : le dernier titre écouté, '
        'avec sa pochette et sa barre de progression. On le touche, et la file '
        'repart où on l\'avait laissée — à la piste et à la seconde près, même '
        'après que le téléphone a fermé l\'app',
    'Ce qu\'on écoutait est gardé sur le téléphone : la question arrive dans '
        'la voiture avant que la session ne soit rétablie, souvent sans '
        'réseau. Tant qu\'on n\'a encore rien écouté, la vignette propose la '
        'lecture aléatoire plutôt que de laisser un écran vide',
    'Le diagnostic Android Auto note aussi, désormais, ce qu\'on a demandé à '
        'jouer et pourquoi ça n\'a pas marché — il ne montrait jusqu\'ici que '
        'les listes affichées',
  ]),
  ReleaseNote('3.29.0', [
    'La chanson qui se termine n\'a plus l\'air de remonter le son pendant le '
        'croisement. La mise à niveau du passage comparait le volume MOYEN des '
        'deux morceaux ; or un croisement ne fait pas jouer des moyennes, il '
        'fait jouer la FIN de l\'un et le DÉBUT de l\'autre',
    'Et une chanson finit presque toujours plus bas qu\'elle n\'a joué : sur '
        'ta bibliothèque, cinq décibels de moins en médiane, cinquante-six '
        'titres sur soixante. Le titre suivant arrivait donc au volume moyen '
        'du précédent — plus fort que ce que le précédent faisait encore '
        'entendre',
    'Le serveur mesure maintenant les deux bords qui se croisent vraiment, et '
        'c\'est là-dessus que le titre entrant se cale. Rien d\'autre ne '
        'change : toujours six décibels de rattrapage au plus, jamais de '
        'poussée vers le haut, et le retour au volume normal une fois le '
        'passage terminé',
    'Chaque morceau se remesure une fois de plus, tout seul, à sa première '
        'lecture',
  ]),
  ReleaseNote('3.28.0', [
    'Le passage d\'un titre à l\'autre n\'enfle plus du tout : le titre '
        'suivant, quand il est GRAVÉ PLUS FORT que celui qui s\'achève, monte '
        'jusqu\'au niveau de ce dernier et pas au-dessus. Il retrouve son '
        'propre volume ensuite, tout doucement, une fois le passage terminé',
    'Le serveur mesurait déjà le niveau de chaque morceau sans que personne '
        's\'en serve : c\'est lui qui règle maintenant la hauteur du '
        'croisement, jusqu\'à six décibels de rattrapage',
    'La courbe du croisement a changé de loi : chaque titre passe à −4,5 dB '
        'au milieu du fondu au lieu de −3 dB. Deux musiques différentes qui '
        'jouent ensemble s\'entendent plus fort que la somme de leurs '
        'puissances — le passage compense désormais cet écart, sans creuser '
        'de trou pour autant',
  ]),
  ReleaseNote('3.27.0', [
    'Les paroles ne sont plus tranchées par des « … » : une phrase trop '
        'longue s\'étale d\'abord sur DEUX LIGNES, et ne rétrécit que si deux '
        'lignes ne suffisent toujours pas',
    'La place réservée à chaque phrase suit sa vraie hauteur : les phrases à '
        'deux lignes ne se marchent plus dessus et le défilement tombe pile '
        'sur la phrase chantée',
    'La mesure tient compte de la largeur de la feuille et de la taille de '
        'texte réglée dans le téléphone : à l\'horizontale ou en gros '
        'caractères, chaque phrase reste entière',
  ]),
  ReleaseNote('3.26.0', [
    'Le thème « Apple Liquid Glass » se voit enfin : il repeint aussi le FOND '
        'D\'ÉCRAN. De grands halos colorés, tirés de ta couleur d\'accent, '
        'remplacent le gris perle — sans rien dessous, la vitre la plus fine '
        'ne rendait qu\'un gris',
    'La vitre a maigri de moitié et le flou a doublé de profondeur : les '
        'barres, le dock et le mini-lecteur laissent désormais passer la '
        'couleur du dessous au lieu de la masquer',
    'Les arêtes accrochent bien plus la lumière : on voit la tranche du '
        'verre, un reflet rasant en haut à gauche et l\'éclat dans l\'angle',
    'Le verre déborde des barres : les gélules de filtre, les champs de '
        'recherche, les feuilles et les boîtes de dialogue deviennent du '
        'verre eux aussi',
    'Ta couleur et le clair/sombre restent les tiens, et le verre de toujours '
        'ne bouge pas d\'un pixel quand le thème est éteint',
  ]),
  ReleaseNote('3.25.0', [
    'Un thème « Apple Liquid Glass » rejoint le rétro Winamp dans les thèmes '
        'à part : Paramètres → Apparence, l\'interrupteur juste au-dessus du '
        'rétro. Les deux s\'excluent, et l\'éteindre ramène le verre de '
        'toujours',
    'C\'est le verre d\'iOS 26 : une vitre bien plus fine (on lit au '
        'travers), un flou plus profond qui ravive les couleurs du dessous, '
        'des arêtes qui accrochent la lumière et des angles en superellipse — '
        'les commandes deviennent des gélules, les boutons ronds de vraies '
        'lentilles',
    'À la différence du rétro, il ne confisque rien : ta couleur d\'accent et '
        'le clair/sombre restent les tiens. Chez Apple, le verre est une '
        'matière, pas une palette',
    'La mise en page ne bouge pas d\'un pixel : mêmes écrans, mêmes gestes, '
        'seule la peinture change',
  ]),
  ReleaseNote('3.24.0', [
    'Il n\'y a plus de catalogue public : le catalogue a été transféré dans '
        'ta liste, telle que tu la voyais. Tes favoris et tes dossiers ont '
        'suivi, et ce que tu avais déjà supprimé n\'est pas revenu',
    'Chaque utilisateur a désormais sa propre liste : renommer, changer '
        'l\'icône ou supprimer une station ne regarde plus que toi. Une '
        'suppression est définitive — il n\'y a plus de station « masquée »',
    'Les jumelles du catalogue ont fondu au passage : une centaine de '
        'stations servaient le même flux sous deux noms, il n\'en reste '
        'qu\'une de chaque',
    'Le menu « … » propose « Importer le catalogue Radio Browser » pour '
        'reprendre les stations canadiennes quand tu veux, sans jamais '
        'dupliquer celles que tu as déjà',
  ]),
  ReleaseNote('3.23.0', [
    'La liste de radios est la tienne : ce que tu y supprimes s\'en va pour '
        'de bon, station du catalogue public comprise. Ta liste n\'est plus '
        'celle de tout le monde',
    'Pour épurer vite : « Sélectionner », puis « Tout sélectionner » — qui ne '
        'prend que ce qui est affiché. Filtre par genre ou cherche un mot, et '
        'tout ce lot part d\'un seul geste',
    'Le catalogue public s\'éteint dans le menu « … » : il ne reste alors que '
        'tes stations. Tes favoris peuvent être recopiés dans ta liste avant '
        'la fermeture, et « Copier dans ma liste » fait de même pour '
        'n\'importe quelle station du catalogue',
    'Rien n\'est perdu : « Restaurer les stations supprimées » ramène tout le '
        'catalogue, et le rallumer se fait au même endroit',
  ]),
  ReleaseNote('3.22.0', [
    'L\'accueil ne dit plus bonjour : la mouette et le nom « Gullify » '
        'prennent toute la place en haut de l\'écran',
  ]),
  ReleaseNote('3.21.0', [
    'Un album rangé sous le mauvais nom se corrige depuis sa fiche : '
        '« Corriger l\'artiste ou le titre » dans le menu. Les deux noms '
        'arrivent déjà remplis — il n\'y a que la faute à réparer',
    'L\'album va REJOINDRE l\'artiste ainsi nommé, celui qui existe déjà avec '
        'ses autres albums, sa photo et ses favoris ; s\'il s\'y trouve un '
        'album du même titre, les deux n\'en font plus qu\'un. L\'artiste '
        'laissé sans rien s\'en va',
    'Les tags des fichiers sont corrigés au passage — sinon le prochain scan '
        'ramènerait l\'erreur — sans toucher à la pochette ni au reste du '
        'tag. Les fichiers ne changent pas de dossier',
  ]),
  ReleaseNote('3.20.0', [
    'La jaquette d\'un album se choisit maintenant à la main : « Changer la '
        'jaquette » dans le menu de la page d\'album. Les pochettes que '
        'YouTube Music et Deezer ont sous « artiste titre » s\'affichent avec '
        'leur titre et leur artiste — de quoi repérer la compilation ou '
        'l\'album homonyme avant de choisir',
    'Rien ne convient ? Le texte cherché se change (titre original, '
        'réédition, album mal taggé), un lien se colle, ou une image du '
        'téléphone fait l\'affaire',
    'La jaquette choisie passe devant le folder.jpg du dossier et devant la '
        'pochette des tags, jusque dans Android Auto — sans jamais toucher '
        'aux fichiers de musique. « Jaquette automatique » rend la main à ce '
        'que le serveur trouve tout seul',
  ]),
  ReleaseNote('3.19.0', [
    'Correctif du fondu enchaîné : le passage d\'un titre à l\'autre enflait, '
        'parce que le titre qui arrive commençait à monter pendant que le '
        'précédent jouait encore à plein volume. Les deux musiques '
        's\'ajoutaient — maintenant le suivant attend sagement, muet, le temps '
        'de son intro, et les deux volumes réunis ne pèsent jamais plus qu\'un '
        'seul titre',
    'Accueil : la mouette et « Gullify » en en-tête, à la place du mot '
        '« Accueil » — l\'onglet disait déjà où on est',
  ]),
  ReleaseNote('3.18.0', [
    'Le tampon d\'avance : les prochains titres de la file descendent sur le '
        'téléphone pendant que tu écoutes celui d\'avant, et se jouent depuis '
        'là. Un tunnel, un ascenseur ou un bout de campagne ne coupent plus '
        'la musique — il n\'y a plus rien à demander au réseau au moment de '
        'l\'entendre',
    'Réglable dans Paramètres → Lecture → Tampon d\'avance : de un titre à '
        'toute la file, avec la place que tu lui accordes. Trois titres et '
        '512 Mo par défaut',
    'Le tampon se garde d\'une écoute à l\'autre et s\'efface tout seul : '
        'les plus vieux titres partent quand la place est pleine, jamais ceux '
        'de la file en cours. Rien à voir avec les téléchargements, qui '
        'restent tant que tu ne les supprimes pas',
    'Un titre à la fois, en arrière-plan, pour ne pas gêner ce qui joue. Les '
        'titres déjà téléchargés ne sont pas repris ; le karaoké et la '
        'lecture aléatoire, eux, continuent de passer par le serveur',
  ]),
  ReleaseNote('3.17.0', [
    'Un album entier se prête maintenant comme une chanson : « Partager '
        'l\'album » dans le menu de la page d\'album donne un lien de 24 h '
        'qui s\'ouvre sur la pochette et la liste des titres, à écouter d\'un '
        'bout à l\'autre sans compte',
    'Un artiste se prête pareil, avec toute sa discographie dans l\'ordre des '
        'albums — du plus récent au plus ancien',
    'La page du lien enchaîne les titres toute seule et laisse choisir '
        'lequel écouter ; l\'aperçu envoyé par SMS annonce le nombre de '
        'titres et le temps qu\'il reste au lien',
    'Le lien n\'ouvre que ce qui a été partagé : un titre qui n\'est pas dans '
        'l\'album ou chez l\'artiste prêté reste inaccessible, et tout '
        's\'efface au bout de 24 h comme avant',
  ]),
  ReleaseNote('3.16.0', [
    'Les deux pages ouvertes hors de l\'app portent enfin la nouvelle '
        'mascotte : celle d\'une chanson prêtée (le lien de 24 h) et celle '
        'où les invités rejoignent une partie. Elles montraient encore '
        'l\'ancienne mouette de profil',
    'La marque y est refaite en deux morceaux — la mouette détourée, puis '
        '« Gullify » écrit à côté — au lieu de l\'ancienne image d\'un seul '
        'tenant, dont le mot manuscrit ne se sépare pas du dessin',
    'Une chanson prêtée sans pochette montre la mascotte plutôt qu\'une note '
        'de musique, dans la page comme dans l\'aperçu du lien envoyé par '
        'SMS',
  ]),
  ReleaseNote('3.15.0', [
    'Le rétro Winamp prend le design que tu as dessiné : « chrome & LCD ». '
        'Le gris du châssis devient un vrai chrome en dégradé, les vitres '
        'passent au noir verdâtre et le vert au phosphore',
    'Deux polices bitmap embarquées : Silkscreen pour tout ce qui est GRAVÉ '
        'dans la tôle (titres de section, libellés de boutons, nom de '
        'l\'écran), VT323 pour tout ce qui s\'AFFICHE derrière une vitre. '
        'C\'est le lettrage, plus que la couleur, qui date l\'objet',
    'La barre de navigation devient la rangée de boutons d\'un lecteur de '
        '1999 : des plaques de chrome gravées LIB, SRC, VID, RAD, FAV, JEU, '
        'enfoncées et allumées en vert quand on y est (l\'appui long donne '
        'toujours le nom complet)',
    'Chaque onglet se coiffe de la réglette du châssis : « GULLIFY », les '
        'hachures, et le nom de l\'écran en phosphore à droite',
    'Tout champ de saisie devient un afficheur : recherche, filtres, tout ce '
        'qui se tape s\'écrit en vert sur noir. Les filtres de genre et '
        'd\'année deviennent des onglets de chrome carrés',
    'Dans le lecteur : la pochette est sertie dans une plaque de chrome, la '
        'forme d\'onde passe derrière une vitre (vert vif pour ce qui est '
        'joué, vert éteint pour la suite), et les actions du bas prennent '
        'chacune leur case',
    'L\'ambre rejoint le vert comme seconde couleur du châssis, et la barre '
        'de titre du lecteur passe du bleu au chrome, nom d\'album gravé en '
        'phosphore',
    'Le mini-lecteur affiche le titre et l\'artiste derrière une vitre, comme '
        'la ligne défilante de l\'original',
  ]),
  ReleaseNote('3.14.0', [
    'Une idée peut désormais porter des pièces jointes : captures d\'écran, '
        'maquettes, logs, n\'importe quel fichier (10 Mo chacun, 20 par '
        'idée). Le trombone est à côté du champ de saisie pour une nouvelle '
        'idée, et sous chaque idée déjà notée',
    'Les fichiers joints se revoient dans l\'app (aperçu des images), '
        's\'ouvrent hors de l\'app d\'un appui, et se retirent un par un',
    'Claude LIT ces fichiers avant de coder quand tu lui confies l\'idée : '
        'une capture de ce qui cloche vaut mieux qu\'un paragraphe',
  ]),
  ReleaseNote('3.13.0', [
    'Le rétro Winamp ressemble enfin à un Winamp : ce qui manquait n\'était '
        'pas la couleur mais le relief. Les plaques ont un vrai biseau à deux '
        'traits (clair puis très clair en haut, sombre puis très sombre en '
        'bas) et le gris a le grain de la tôle brossée',
    'Le lecteur a sa barre de titre bleu nuit hachurée, avec le nom de '
        'l\'album gravé au milieu (toujours cliquable) et la petite croix '
        'carrée à droite',
    'Le temps n\'est plus écrit mais DESSINÉ, segment par segment, segments '
        'éteints visibles en filigrane comme sur un vrai afficheur',
    'L\'analyseur de spectre passe en colonnes de blocs, du vert à l\'ambre, '
        'avec le plot de crête gris qui retombe',
    'Deux cases creuses à côté du temps : le format du fichier (MP3, FLAC…) '
        'et le rang du titre dans la file, plus les voyants MONO/STEREO',
    'Boutons de transport gravés à la place des ronds : précédent, '
        'lecture/pause, suivant, et les bascules aléatoire/répétition qui '
        'restent enfoncées quand elles sont actives',
    'La barre de position devient une rainure creuse avec son bloc '
        'coulissant, la pochette s\'encastre dans un cadre creux, et le '
        'bouton d\'accueil du dock devient une plaque carrée',
    'Correction : un titre assez court pour ne pas défiler pouvait faire '
        'râler l\'afficheur au moment de quitter le lecteur',
  ]),
  ReleaseNote('3.12.0', [
    'Un thème rétro Winamp, à part des autres : Paramètres → Apparence → '
        '« Rétro Winamp ». Châssis gris métal, plaques biseautées (lumière en '
        'haut, ombre en bas), angles carrés, pochettes carrées et vert '
        'd\'afficheur partout',
    'Le lecteur retrouve son afficheur : temps en gros chiffres verts (les '
        'deux points clignotent à la pause, comme avant), titre qui défile '
        'quand il est trop long, et l\'analyseur de spectre qui saute à côté',
    'Le mini-lecteur passe lui aussi en chasse fixe verte',
    'Rien n\'a bougé d\'un pixel : mêmes écrans, même mise en page, mêmes '
        'gestes — seule la peinture change. En l\'éteignant, le verre revient '
        'exactement comme il était, avec ta couleur et ton mode',
    'Tant qu\'il est levé, l\'accent et le mode clair/sombre n\'ont pas de '
        'prise : Winamp n\'a qu\'une seule tête',
  ]),
  ReleaseNote('3.11.0', [
    'Un réveil matinal : Paramètres → Lecture → « Réveil ». Une heure, des '
        'jours, et la musique de ton choix — le réveil pioche dans toute la '
        'bibliothèque, un genre, une playlist ou tes favoris, comme les jeux',
    'Le son monte doucement : la musique démarre à volume nul et met le temps '
        'réglé (5 min par défaut, jusqu\'à 20) à atteindre son niveau. Le '
        'volume média est monté tout seul au réveil, puis remis comme il était '
        'quand tu arrêtes',
    'À l\'heure dite, Android réveille le téléphone et Gullify s\'ouvre tout '
        'seul, par-dessus l\'écran verrouillé : « Encore 9 min », « Garder la '
        'musique » ou « Arrêter », les trois dans le bas de l\'écran',
    'Ou un buzz, au choix : une sonnerie embarquée dans l\'app. Elle prend '
        'aussi le relais toute seule si le serveur est injoignable au petit '
        'matin — un réveil ne dépend pas du réseau',
    'Et un filet : si l\'app ne démarrait pas, la sonnerie du système se '
        'déclenche 90 secondes plus tard. L\'alarme se repose seule après un '
        'redémarrage du téléphone',
    'Avant de lui faire confiance : « Sonner dans une minute », en bas de '
        'l\'écran du réveil — écran éteint, téléphone posé, pour vérifier une '
        'bonne fois que la sonnerie ouvre bien l\'app',
  ]),
  ReleaseNote('3.10.0', [
    'La bibliothèque se parcourt aussi par année : nouvel onglet « Années », '
        'entre Genres et Favoris. Les millésimes sont rangés par décennie, du '
        'plus récent au plus ancien, avec la mosaïque de leurs pochettes',
    'Chaque année a sa radio : « Radio 1994 » lance les titres sortis cette '
        'année-là, mélangés — une machine à remonter le temps qui ne pioche '
        'que dans ta collection',
    'La page d\'une année montre aussi tous ses albums, comme une page de '
        'genre',
    'L\'année vient de l\'album : un album sans date n\'apparaît nulle part '
        'ici. Sa date se complète depuis l\'éditeur de tags',
  ]),
  ReleaseNote('3.9.0', [
    'Le fondu enchaîné se cale enfin sur la musique et non sur le chronomètre : '
        'le serveur écoute les bords de chaque titre (son niveau, une demi-'
        'seconde à la fois) et le lecteur taille son passage dessus',
    'Un titre qui finit sur un blanc de fichier ne fait plus attendre : le '
        'suivant démarre avant le silence, jamais de trou entre deux morceaux',
    'Un titre qui s\'éteint tout seul se fait couvrir pendant toute sa '
        'descente — jusqu\'au double de la durée réglée. Un titre qui s\'arrête '
        'net, lui, garde le croisement réglé : c\'est là qu\'il sert vraiment',
    'Un morceau qui met du temps à démarrer part en avance, pour que sa '
        'première vraie note tombe pile à la fin de la précédente. Celui qui '
        'joue, lui, garde son volume tant que rien ne vient le remplacer',
    'Réglable dans Paramètres → Lecture → Fondu → « Croisement intelligent ». '
        'Sans réseau, ou sur un titre que le serveur ne sait pas mesurer, le '
        'croisement reprend simplement la durée réglée',
  ]),
  ReleaseNote('3.8.0', [
    'La photo d\'un artiste se change à la main : page de l\'artiste → les '
        'trois points en haut à droite → « Changer l\'image », au même endroit '
        'que le genre',
    'Le dialogue montre d\'abord ce que YouTube Music et Deezer ont sous ce '
        'nom : une tape sur la bonne photo, c\'est réglé',
    'Chaque proposition porte le nom que le service lui donne — c\'est là '
        'qu\'on voit que c\'est l\'homonyme qui avait été trouvé. Le nom '
        'cherché se change alors dans le champ du haut, pour tomber sur le bon '
        'artiste',
    'Sinon : coller un lien vers n\'importe quelle image du web, ou choisir '
        'une photo du téléphone',
    '« Image automatique » défait le choix : l\'image du dossier de l\'artiste, '
        'ou celle trouvée sur le web, reprend la main',
  ]),
  ReleaseNote('3.7.0', [
    'Les jeux ressemblent enfin à des jeux : un vinyle tourne pendant '
        'l\'extrait, le chrono fait le tour du disque et rougit sur la fin, et '
        'une onde sonore montre que ça joue même le son au minimum',
    'Bonne réponse : la carte s\'illumine, des étincelles partent et le '
        'téléphone donne une petite tape. Mauvaise réponse : l\'écran encaisse '
        'le coup. La pochette, elle, se retourne pour se montrer',
    'Tout ce sur quoi on tape vite est descendu dans la zone du pouce, en plus '
        'gros : réponses franches qui s\'enfoncent sous le doigt, et zones de '
        'dépôt de la frise Chrono deux fois plus larges et lumineuses',
    'Le score saute quand il monte, le record se porte en médaille dorée, et '
        'la fin de partie fête les records comme il se doit',
    'La page des invités d\'une partie reçoit le même traitement : vinyle, '
        'onde, chrono en anneau, vibrations et étincelles — sans rien alourdir '
        'au chargement',
  ]),
  ReleaseNote('3.6.0', [
    'Le fondu entre les titres devient un vrai fondu enchaîné : le titre '
        'suivant démarre et monte pendant que celui en cours descend, les deux '
        'dans les oreilles en même temps. Plus de silence au milieu du passage',
    'Le croisement dure la durée réglée dans Paramètres → Lecture → Fondu, sans '
        'jamais prendre plus du tiers d\'un titre : un interlude de vingt '
        'secondes s\'entend encore tout seul',
    'Le titre suivant se charge dix secondes à l\'avance : il part à l\'heure, '
        'même en 4G. Le dernier titre d\'une file, lui, n\'a personne avec qui '
        'se croiser — il s\'éteint seul, comme avant',
    'Pause, saut, retour en arrière ou nouvelle file en plein croisement : le '
        'titre sortant se tait aussitôt, jamais deux musiques qui traînent '
        'ensemble. L\'ordre aléatoire en cours est conservé d\'un titre à '
        'l\'autre',
  ]),
  ReleaseNote('3.5.0', [
    'Le fondu du lecteur se règle enfin : Paramètres → Lecture → Fondu. Le '
        'son monte au démarrage et descend avant la pause, sur la durée que '
        'tu choisis — d\'une demi-seconde à huit secondes',
    'Nouveau : le fondu entre les titres (à activer dans le même écran). '
        'Chaque titre s\'efface sur sa fin et le suivant se lève, sans trou '
        'entre les deux; ça vaut aussi pour un titre rejoué en boucle',
    'Le fondu ne peut plus rester coincé : reprise en arrière, saut au titre '
        'suivant, fin de la file ou réglage éteint en cours de route, le '
        'volume revient toujours. Et une radio, qui n\'a pas de fin, n\'est '
        'jamais fondue',
    'Appuyer sur lecture pendant le fondu de la pause annule la pause au lieu '
        'de couper le son au milieu',
  ]),
  ReleaseNote('3.4.0', [
    'Les nouveautés de la recherche ne sont plus un fourre-tout : elles sont '
        'reclassées pour toi, avec en tête les sorties des artistes que tu '
        'écoutes déjà — c\'est écrit sous leur titre',
    'Les pièces radiophoniques allemandes, les mixes de DJ, la musique de gym '
        'et les sorties écrites dans un alphabet qu\'on ne lit pas descendent '
        'au fond de la liste, et les albums déjà rangés dans la bibliothèque '
        'avec eux',
    'Gullify annonce maintenant le Canada à YouTube Music, pour que la '
        'recherche parle du bon marché (la page des nouveautés, elle, est la '
        'même partout dans le monde : le pays n\'y change rien)',
  ]),
  ReleaseNote('3.3.0', [
    'L\'onglet Recherche, champ vide, affiche maintenant les nouveautés de '
        'YouTube Music : les sorties du moment, prêtes à télécharger d\'un tap '
        'comme n\'importe quel résultat',
    'Seuls les ALBUMS sont listés — les singles et les EP, qui noyaient la '
        'liste, sont écartés',
    'La liste montre douze sorties, « Charger plus » en révèle davantage; les '
        'albums déjà dans la bibliothèque portent leur pastille',
  ]),
  ReleaseNote('3.2.0', [
    'La mouette du médaillon des pages vides — celle qu\'on voit quand il n\'y '
        'a aucune notification — n\'est plus teintée de la couleur d\'accent '
        'choisie : elle est gravée en noir et blanc sur un disque de verre '
        'neutre',
    'Elle est aussi recentrée : elle était calée vers le bas du disque et '
        's\'y dissolvait, elle est maintenant posée bien au milieu',
  ]),
  ReleaseNote('3.1.0', [
    'Dans Android Auto, un genre s\'écoute maintenant d\'un seul geste : '
        '« Tout lire » et « Lecture aléatoire » attendent en tête de la liste '
        'des artistes du genre. Plus besoin de choisir un artiste, puis un '
        'album, puis un titre au volant',
    'Les listes « Genres » et « Albums » ont elles aussi leurs deux entrées '
        'de lecture en tête, comme « Artistes » : partout où il y a plusieurs '
        'choix, la musique peut partir tout de suite',
    'Le « Tout lire » d\'un genre suit l\'ordre artiste, album, piste ; '
        '« Lecture aléatoire » brasse tout le genre',
  ]),
  ReleaseNote('3.0.0', [
    'La mouette a un nouveau visage : elle regarde droit devant, casque sur '
        'les oreilles et grosses lunettes. C\'est elle qu\'on retrouve '
        'maintenant sur l\'icône de l\'app, sur l\'écran de démarrage, à la '
        'connexion et sur les pages vides',
    'Le fond de l\'icône passe au bleu-vert de la nouvelle mascotte, et '
        'l\'icône des notifications de lecture suit la même silhouette',
    'Le site et les pages de partage arborent la nouvelle frimousse : '
        'favicon, icône d\'écran d\'accueil et pochette par défaut des albums '
        'sans jaquette',
  ]),
  ReleaseNote('2.99.0', [
    'Les albums téléchargés dernièrement avaient chaque titre en double : deux '
        'téléchargements qui se terminaient en même temps lançaient deux '
        'analyses du même artiste, et chacune inscrivait le même fichier. Les '
        'doublons déjà en base ont été fusionnés — favoris, listes de lecture '
        'et compteurs d\'écoute conservés — et la base refuse maintenant '
        'd\'inscrire deux fois le même fichier',
    'Un album (ou un titre) déjà dans la bibliothèque porte la pastille '
        '« Déjà là » dans la recherche YouTube Music, et la fenêtre de '
        'téléchargement le rappelle avant de lancer quoi que ce soit. Un '
        '« Télécharger quand même » reste là pour reprendre un album '
        'incomplet',
    'Un album déjà en cours de téléchargement ne se relance plus du tout : '
        'deux téléchargements dans le même dossier, c\'est exactement ce qui '
        'fabriquait les doublons',
  ]),
  ReleaseNote('2.98.0', [
    'Une chanson se prête : « Partager » — dans le menu d\'un titre (appui '
        'long) comme dans le lecteur — tire un lien à envoyer par SMS. La '
        'personne qui le reçoit écoute la chanson dans son navigateur, sans '
        'compte et sans installer quoi que ce soit, exactement comme une '
        'invitation à une partie',
    'Le lien s\'efface tout seul au bout de 24 h : passé ce délai la page ne '
        'montre plus rien. « Désactiver le lien » le coupe avant l\'heure si '
        'on se ravise',
    'Un lien n\'ouvre qu\'une seule chanson — jamais la bibliothèque, jamais '
        'le fichier d\'origine. La page d\'écoute a le visage de l\'app '
        '(verre nuit, pochette, bouton d\'accent) et l\'aperçu du SMS montre '
        'déjà la pochette et le titre',
  ]),
  ReleaseNote('2.97.0', [
    'La page d\'un artiste qui vient d\'entrer dans la bibliothèque ne reste '
        'plus sur le logo Gullify : le serveur va chercher sa photo au moment '
        'où la page s\'ouvre, sur YouTube Music d\'abord (le catalogue '
        'québécois et francophone y est bien mieux servi), sur Deezer ensuite. '
        'Une fois trouvée, elle est gardée — et l\'artiste l\'a aussi dans les '
        'listes, la voiture et la notification',
    'La photo n\'est prise que si le nom correspond vraiment : YouTube et '
        'Deezer répondent toujours quelque chose, même à un nom qui n\'existe '
        'pas, et coller le visage d\'un autre est pire que pas de photo du '
        'tout. Un artiste que personne n\'a n\'est pas redemandé avant une '
        'semaine, et les fourre-tout (« Unknown Artist », « Various Artists ») '
        'sont écartés',
    'La recherche ne part que depuis la page d\'un artiste, une à la fois : '
        'ouvrir la liste des artistes n\'en déclenche aucune',
  ]),
  ReleaseNote('2.96.0', [
    'Le mini-lecteur répond au pouce : un balayage vers le haut ouvre le '
        'lecteur complet, un balayage vers le bas ferme le lecteur — le son '
        's\'arrête, la file se vide et la carte disparaît du bas de l\'écran',
    'Fermer reste rattrapable : « Annuler » rouvre la file à la piste et à la '
        'seconde où elle s\'était arrêtée. Le balayage vers le bas demande un '
        'geste un peu plus franc que vers le haut, tant qu\'à couper la musique',
    'Le balayage horizontal ne change pas : à gauche la piste suivante, à '
        'droite la précédente',
  ]),
  ReleaseNote('2.95.0', [
    'Les écrans vides (aucune notification, aucun favori, aucun téléchargement, '
        'aucun résultat…) changent de visage : la mouette y est gravée en '
        'monochrome — une seule teinte, tirée de la couleur d\'accent — au '
        'creux d\'un médaillon de verre, et se dissout vers le bas au lieu de '
        's\'arrêter net',
    'Le trou de transparence en pleine poitrine de la mascotte est bouché : le '
        'fond se voyait à travers elle, et ça se remarquait surtout sur base '
        'sombre. La correction profite aussi aux écrans de connexion et de '
        'serveur, qui l\'affichent en couleurs',
  ]),
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

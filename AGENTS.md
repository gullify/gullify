# GulliFY — notes pour Claude

Serveur de musique (PHP 8.2 + MySQL, sans framework) et app Flutter `app/` (APK + web servi dans
`public/app`). Lire aussi `~/cerveau/AGENTS.md` (l'atelier) et `~/gullios/CONTRAT-GESTION.md`.

- Schéma : `setup/schema.sql` (installations neuves) + `AppConfig::runMigrations()` (colonnes ajoutées
  aux bases existantes, à la première connexion). Toute colonne nouvelle va aux DEUX endroits.
- Publication : `./build-app.sh "notes"` (APK + `version.json` sur download.gullify.app, puis le web),
  et pour le serveur : monter `VERSION`, puis `./scripts/publier-image.sh "notes"` (image + `serveur.json`).
  Toute commande qui lance Gradle passe par `flock ~/.verrou-gradle …`.
- Essais : `scripts/test-*.php`. Le contrat de gestion : `scripts/test-maison-gestion.php`, sur une base
  MySQL JETABLE seulement (il efface des comptes ; exige `TEST_JETABLE=oui`, voir son en-tête).

## « Ma maison » — contrat de gestion v2 (`scripts/maison-gestion.php`)
- On se connecte par NOM D'UTILISATEUR : pas de courriel. `modifier` accepte `nom=` (nom affiché,
  `full_name`) ; `courriel=` répond une erreur. Le nom d'utilisateur ne change jamais (il range les
  favoris, listes, historique).
- Secret temporaire (`creer`, `reinitialiser`, `definir`) → `users.must_change_password = 1` :
  la connexion réussit avec `doit_changer: true`, puis tout répond 403 `changement_requis`
  (API v2, points d'entrée historiques via `auth_required.php`, `stream.php`) sauf
  `auth.php?action=me|logout|change_password`. Subsonic (`public/rest`) refuse ce compte
  et ne retient jamais le mot de passe temporaire. Nouveau mot de passe : 8 caractères au moins.
- Compte désactivé : connexion refusée (« Ce compte est désactivé. », seulement si le mot de passe
  est bon), sessions et mot de passe Subsonic révoqués, Subsonic refusé.

### Politique de `supprimer`
Supprimés : le compte, ses sessions (appareils), sa photo, ses listes de lecture, ses favoris (titres,
artistes, albums), son historique d'écoute, ses notifications, genres perso, radios perso et réglages
radio, abonnements et progression de podcasts, liens de partage, son profil de goûts « Pour toi » (`gouts_*`), et l'INDEX de sa bibliothèque en base
(`artists`/`albums`/`songs`/`library_stats` à son nom — reconstruit par un scan, comme le fait déjà
un rescan complet). La MUSIQUE (les fichiers) n'est JAMAIS touchée. Refusé pour le dernier
administrateur. GulliFY n'a pas de « données précieuses orphelines » : rien d'autre n'est refusé.

## Comptes de la maison (`~/gullios/CONTRAT-COMPTES.md`, serveur 1.5.0, app 3.81.0)
- Double mode, côté SERVEUR seulement : `COMPTES_URL` (+ `COMPTES_JETON`) absent du `.env` → tout
  comme avant. Présent → `auth.php?action=login` prend `{courriel, password}` et passe par Comptes
  (`src/Comptes.php`) ; la connexion par nom d'utilisateur est refusée partout (`Auth::verifyPassword`).
  `ping.php` dit au client le mode : `connexion: courriel | nom_utilisateur`.
- Compte local trouvé par `users.compte_id` (+ `email` recopié), créé à la 1re connexion : non admin,
  `music_directory = '.'`, nom d'utilisateur tiré du nom, mot de passe local aléatoire inutilisé.
  Photo de Comptes recopiée si `photo: true` (jamais retirée localement).
- `change_password` → POST `/changer` (10 car.), lève `must_change_password`, ferme les autres sessions.
- Gestion : `lier <id> <compte_id>` (efface l'ancien mot de passe Subsonic retenu), `personnes` rend
  `compte_id` et `courriel` ; `creer` / `reinitialiser` / `definir` → erreur « gérés par les comptes ».
- Subsonic en mode Comptes : SEUL le mot de passe d'application (`auth.php?action=subsonic`,
  `subsonic_generer` — montré une fois —, `subsonic_revoquer` ; colonne `subsonic_password`) ouvre
  `/rest` ; `u` = nom d'utilisateur GulliFY ou courriel. Écran app : Paramètres → Clients Subsonic.
- `empreinte <id>` (contrat v1.1, serveur 1.6.0) : `password_hash` tel que stocké, pour l'import dans Comptes à la
  bascule (jamais affiché ; refusé si `must_change_password` ou format ni bcrypt ni argon2). Essais dans
  `scripts/test-maison-gestion.php`.
- Essais : `scripts/test-comptes.php` (faux Comptes `scripts/test-comptes-faux.php`), base jetable.

## Genres multiples et origine (serveur 1.20.0, app 3.93.0)
- Un artiste a jusqu'à 3 genres (`artiste_genres`, rang 0 = principal, recopié dans `artists.genre` pour
  Subsonic, les jeux et les vieux écrans) et une ORIGINE à part (`artists.origine` : liste fermée de
  `src/Origine.php` — Québec, Acadie, Canada, France…). Helper : `src/ArtisteGenres.php`.
- Sources (`GenreLookup::suggest`) : Last.fm d'abord (clé `LASTFM_API_KEY`), puis MusicBrainz, Deezer,
  Apple Music. Origine : étiquettes Last.fm, sinon région MusicBrainz (on remonte la ville → province).
  « canadian » et « french » sont ambigus (langue, Québec) : MusicBrainz tranche quand il sait.
- `scan-genres.php` sans `--force` : artistes sans genre + ceux pas encore analysés (`genres_analyse`) ;
  garde le principal, ajoute secondaires et origine, nettoie les genres bruts (« Music », « Indie »).
  `genres_manuel` / `origine_manuelle` (posés par l'app) : jamais touchés, même avec `--force`.
- API : `get_artists_by_genre` (+ `origine=`), `get_origines`, `get_all_albums&origine=`,
  `set_artist_genres` (genres JSON + `origine`), `GameSource` accepte `origines` (croisé au vivier).

## Lecture automatique hors de la bibliothèque (serveur 1.21.0, app 3.95.0)
- `pour-toi.php?action=suite&ailleurs=1` (+ `artistes=` noms séparés par `\n`, `exclus_ext=yt:ID,bc:ID`) :
  `GoutsRadio::suite` sans replis (genre/favoris) ; si la bibliothèque est « à sec » (`etat.sec` :
  moins de 4 artistes proches) ou ne remplit pas `n`, `src/GoutsAilleurs.php` ajoute jusqu'à 5 titres
  d'artistes proches qu'on n'a pas (`artistes_similaires` + `gouts_choix`), un par artiste, YouTube Music
  (`ytmusic_search.py top_songs`, artiste vérifié) puis Bandcamp. Cache par artiste dans
  `/tmp/gullify-ailleurs` (14 j, 1 j si vide). Fiche d'ailleurs = `externe` au lieu d'`id`.
  Rien du tout → l'ancienne suite avec replis. Sans `ailleurs=1` (vieilles apps) : inchangé.
- App : `suiteMixte`, fiches `ailleursMediaItem` (extras `previewVideoId` ou `bandcampTrack`, `bcUrl`,
  `sourceAlbum`), `ailleursKeyOf`. Un titre d'ailleurs (pré-écoute de la recherche comprise) a sa suite.
  Bouton « Télécharger » du lecteur (`widgets/download_ailleurs_button.dart`) à la place du cœur.
- Essais : `scripts/test-gouts.php` (section « Ailleurs »), `app/test/ailleurs_test.dart`.

## Aléatoire de la maison en voiture (serveur 1.22.0, app 3.97.0)
- `users.php?action=random&user=X` (une autre personne, compte actif) ou `user=*` (toute la maison, la sienne
  comprise, dédoublonnée par `file_path`) : même forme que `library.php random_songs`.
- Android Auto : Bibliothèque → « Bibliothèques de la maison » (`BrowseIds.maison`), éléments jouables
  `MAISON_SHUFFLE_<username|*>`. Essai : `app/test/aa_play_all_test.dart`.

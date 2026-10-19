# GulliFY — notes pour Claude

Serveur de musique (PHP 8.2 + MySQL, sans framework) et app Flutter `app/` (APK + web servi dans
`public/app`). Lire aussi `~/CLAUDE.md` (l'atelier) et `~/gullios/CONTRAT-GESTION.md`.

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
radio, abonnements et progression de podcasts, liens de partage, et l'INDEX de sa bibliothèque en base
(`artists`/`albums`/`songs`/`library_stats` à son nom — reconstruit par un scan, comme le fait déjà
un rescan complet). La MUSIQUE (les fichiers) n'est JAMAIS touchée. Refusé pour le dernier
administrateur. GulliFY n'a pas de « données précieuses orphelines » : rien d'autre n'est refusé.

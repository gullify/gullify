# TODO — Gullify

Restes connus après la nuit du 2026-07-02 (v2.1.0). Les gros manquants de
l'app (stats, recherche/téléchargement YouTube, auto-update, populaires +
suggestions sur l'accueil) sont faits.

## À valider sur appareil réel
- [ ] Auto-update de bout en bout : installer la 2.0.0, vérifier que la
      2.1.0 est proposée, téléchargée et installée (permission « sources
      inconnues » au premier essai).
- [ ] Android Auto (browse tree implémenté, jamais testé en voiture).
- [ ] Égaliseur sur device physique.
- [ ] Mode hors-ligne sur device physique.
- [ ] Téléchargement YouTube depuis l'app : lancer un album et vérifier
      queue → scan → apparition dans la bibliothèque.

## Fonctionnalités non portées / non commencées
- [ ] Phase 5 : build iOS + soumission aux stores.
- [ ] Refresh automatique du token (`auth.php?action=refresh` existe côté
      serveur; l'app déconnecte sur 401 au lieu de rafraîchir).
- [ ] Écrans admin (scan bibliothèque, doublons, stockage) — endpoints v2
      disponibles (`scan.php`, `admin.php`, `storage.php`).
- [ ] Paroles synchronisées / audio-specs (`audio-specs.php` non branché).

## Infra
- [ ] Configurer l'accès GitHub sur ce serveur : ajouter la clé SSH
      (`~/.ssh/id_ed25519.pub`) au compte GitHub ou en deploy key du dépôt,
      puis `git remote set-url origin git@github.com:gullify/gullify.git`
      et pousser les commits en attente.
- [ ] Sauvegarder `~/keystores/gullify-release.jks` + `app/android/key.properties`
      hors du serveur (perte = plus de mises à jour installables).
- [ ] Décider du sort des APK 0.x-beta dans
      `/home/maxime/gullify-server/downloads/` (ancienne app pixelplay).

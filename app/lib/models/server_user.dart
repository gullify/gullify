/// Un autre utilisateur du serveur, tel qu'exposé par la découverte
/// (`users.php?action=list`) : identité + taille de sa bibliothèque.
class ServerUser {
  const ServerUser({
    required this.id,
    required this.username,
    this.fullName,
    this.artistCount = 0,
    this.albumCount = 0,
    this.songCount = 0,
    this.avatarUrl,
  });

  final int id;
  final String username;
  final String? fullName;
  final int artistCount;
  final int albumCount;
  final int songCount;

  /// URL absolue de la photo de profil, ou null.
  final String? avatarUrl;

  /// Nom à afficher (nom complet si présent, sinon identifiant).
  String get displayName =>
      (fullName != null && fullName!.trim().isNotEmpty) ? fullName! : username;
}

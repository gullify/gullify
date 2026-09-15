import 'api_client.dart';

/// Un utilisateur du serveur, vu par un administrateur.
///
/// Les champs viennent tels quels d'`admin.php?action=list_users`, qui parle
/// encore le vocabulaire de la base (`full_name`, `is_admin`…). Le serveur ne
/// renvoie JAMAIS le mot de passe ni le mot de passe SFTP chiffré : le champ
/// arrive vide, et un champ vide veut dire « garde celui d'avant ».
class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    this.fullName,
    this.isAdmin = false,
    this.isActive = true,
    this.musicDirectory,
    this.storageType = 'local',
    this.sftpHost,
    this.sftpPort = 22,
    this.sftpUser,
    this.sftpPath,
    this.createdAt,
    this.lastLogin,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['username'] as String? ?? '',
    fullName: _text(json['full_name']),
    isAdmin: _flag(json['is_admin']),
    isActive: _flag(json['is_active']),
    musicDirectory: _text(json['music_directory']),
    storageType: json['storage_type'] as String? ?? 'local',
    sftpHost: _text(json['sftp_host']),
    sftpPort: (json['sftp_port'] as num?)?.toInt() ?? 22,
    sftpUser: _text(json['sftp_user']),
    sftpPath: _text(json['sftp_path']),
    createdAt: _text(json['created_at']),
    lastLogin: _text(json['last_login']),
  );

  final int id;
  final String username;
  final String? fullName;
  final bool isAdmin;
  final bool isActive;
  final String? musicDirectory;

  /// « local » ou « sftp ».
  final String storageType;
  final String? sftpHost;
  final int sftpPort;
  final String? sftpUser;
  final String? sftpPath;
  final String? createdAt;
  final String? lastLogin;

  bool get isSftp => storageType == 'sftp';

  /// Nom à afficher (nom complet si présent, sinon identifiant).
  String get displayName =>
      (fullName != null && fullName!.trim().isNotEmpty) ? fullName! : username;

  /// MySQL rend ses booléens en 0/1, parfois en chaîne selon le pilote.
  static bool _flag(dynamic v) =>
      v == true || v == 1 || v == '1' || v == 'true';

  /// Une chaîne vide côté base vaut « pas de valeur ».
  static String? _text(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}

/// Les dossiers de musique disponibles sur le serveur, et la racine sous
/// laquelle ils vivent (affichée pour situer un chemin relatif).
class MusicDirectories {
  const MusicDirectories({required this.basePath, required this.directories});

  final String basePath;
  final List<String> directories;
}

/// L'administration du serveur : comptes, dossiers de musique, stockage.
///
/// Passe par `/api/v2/admin.php`, qui n'accepte que les administrateurs — le
/// serveur relit `is_admin` en base à chaque appel, l'app ne fait que cacher
/// ce qu'un non-administrateur ne pourrait de toute façon pas obtenir.
class AdminRepository {
  AdminRepository(this._client);

  final ApiClient _client;

  Future<List<AdminUser>> users() async {
    final data = await _client.get('admin.php', query: {'action': 'list_users'});
    return [
      for (final u in (data as List<dynamic>? ?? []))
        AdminUser.fromJson(u as Map<String, dynamic>),
    ];
  }

  /// Les dossiers proposables comme bibliothèque d'un utilisateur.
  Future<MusicDirectories> directories() async {
    final data =
        await _client.get(
              'admin.php',
              query: {'action': 'list_directories'},
            )
            as Map<String, dynamic>;
    return MusicDirectories(
      basePath: data['base_path'] as String? ?? '',
      directories: [
        for (final d in (data['data'] as List<dynamic>? ?? [])) d.toString(),
      ],
    );
  }

  /// Crée un compte. Rend son identifiant.
  ///
  /// `admin.php` teste ses drapeaux avec `!empty()` : envoyer « false » les
  /// activerait (la chaîne n'est pas vide). On n'envoie donc la clé que
  /// lorsqu'elle est vraie.
  Future<int> createUser({
    required String username,
    required String password,
    String? fullName,
    bool isAdmin = false,
    String? musicDirectory,
  }) async {
    final data =
        await _client.post(
              'admin.php',
              query: {'action': 'create_user'},
              form: {
                'username': username,
                'password': password,
                if (fullName != null && fullName.isNotEmpty)
                  'full_name': fullName,
                if (isAdmin) 'is_admin': '1',
                if (musicDirectory != null && musicDirectory.isNotEmpty)
                  'music_directory': musicDirectory,
              },
            )
            as Map<String, dynamic>;
    return (data['user_id'] as num?)?.toInt() ?? 0;
  }

  Future<void> deleteUser(int userId) => _client.post(
    'admin.php',
    query: {'action': 'delete_user'},
    form: {'user_id': userId},
  );

  /// Bascule l'accès du compte (actif / suspendu).
  Future<void> toggleActive(int userId) => _client.post(
    'admin.php',
    query: {'action': 'toggle_active'},
    form: {'user_id': userId},
  );

  /// Bascule le rôle d'administrateur.
  Future<void> toggleAdmin(int userId) => _client.post(
    'admin.php',
    query: {'action': 'toggle_admin'},
    form: {'user_id': userId},
  );

  /// Le serveur exige au moins six caractères.
  Future<void> updatePassword(int userId, String password) => _client.post(
    'admin.php',
    query: {'action': 'update_password'},
    form: {'user_id': userId, 'password': password},
  );

  /// Le dossier doit exister sous la racine musicale : sinon le serveur
  /// refuse, et son message dit lequel il n'a pas trouvé.
  Future<void> updateDirectory(int userId, String musicDirectory) =>
      _client.post(
        'admin.php',
        query: {'action': 'update_directory'},
        form: {'user_id': userId, 'music_directory': musicDirectory},
      );

  /// Range le stockage du compte. Un `sftpPassword` vide garde celui déjà
  /// enregistré — le serveur ne le renvoie jamais, on ne peut donc pas le
  /// réémettre.
  Future<void> updateStorage({
    required int userId,
    required bool sftp,
    String? host,
    int port = 22,
    String? user,
    String? password,
    String? path,
  }) => _client.post(
    'admin.php',
    query: {'action': 'update_sftp'},
    form: {
      'user_id': userId,
      'storage_type': sftp ? 'sftp' : 'local',
      if (sftp) ...{
        'sftp_host': host ?? '',
        'sftp_port': port,
        'sftp_user': user ?? '',
        if (password != null && password.isNotEmpty) 'sftp_password': password,
        'sftp_path': path ?? '',
      },
    },
  );

  /// Essaie la connexion SFTP. Rend le message du serveur en cas de succès ;
  /// lève (avec son message) quand la connexion échoue ou que le chemin est
  /// inaccessible. Sans mot de passe, le serveur reprend celui enregistré
  /// pour ce compte.
  Future<String> testSftp({
    required String host,
    int port = 22,
    required String user,
    String? password,
    required String path,
    int? userId,
  }) async {
    final data = await _client.post(
      'admin.php',
      query: {'action': 'test_sftp_connection'},
      form: {
        'sftp_host': host,
        'sftp_port': port,
        'sftp_user': user,
        if (password != null && password.isNotEmpty) 'sftp_password': password,
        'sftp_path': path,
        'user_id': ?userId,
      },
    );
    final map = data is Map<String, dynamic> ? data : const {};
    return map['message'] as String? ?? 'Connexion SFTP réussie';
  }
}

import 'api_client.dart';

/// Espace d'un volume du serveur (musique, données…).
class ServerDisk {
  const ServerDisk({
    required this.label,
    required this.path,
    required this.total,
    required this.free,
    required this.used,
  });

  factory ServerDisk.fromJson(Map<String, dynamic> json) => ServerDisk(
        label: json['label'] as String? ?? '',
        path: json['path'] as String? ?? '',
        total: (json['total'] as num?)?.toInt() ?? 0,
        free: (json['free'] as num?)?.toInt() ?? 0,
        used: (json['used'] as num?)?.toInt() ?? 0,
      );

  final String label;
  final String path;
  final int total;
  final int free;
  final int used;

  /// Part occupée, entre 0 et 1 (0 si le serveur n'a rien pu mesurer).
  double get usedRatio => total > 0 ? (used / total).clamp(0.0, 1.0) : 0;
}

/// Poids d'un dossier du serveur : `bytes` est nul quand le calcul a dépassé
/// son budget de temps et qu'aucune valeur n'avait été mise en cache.
class ServerFolderSize {
  const ServerFolderSize({this.bytes, this.computedAt, required this.path});

  factory ServerFolderSize.fromJson(Map<String, dynamic>? json) =>
      ServerFolderSize(
        bytes: (json?['bytes'] as num?)?.toInt(),
        computedAt: _timestamp(json?['computedAt']),
        path: json?['path'] as String? ?? '',
      );

  final int? bytes;
  final DateTime? computedAt;
  final String path;
}

class ServerLibraryInfo {
  const ServerLibraryInfo({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.genres,
    required this.playlists,
    required this.users,
    required this.duration,
    this.lastScan,
  });

  factory ServerLibraryInfo.fromJson(Map<String, dynamic>? json) =>
      ServerLibraryInfo(
        songs: (json?['songs'] as num?)?.toInt() ?? 0,
        albums: (json?['albums'] as num?)?.toInt() ?? 0,
        artists: (json?['artists'] as num?)?.toInt() ?? 0,
        genres: (json?['genres'] as num?)?.toInt() ?? 0,
        playlists: (json?['playlists'] as num?)?.toInt() ?? 0,
        users: (json?['users'] as num?)?.toInt() ?? 0,
        duration: (json?['duration'] as num?)?.toInt() ?? 0,
        lastScan: _timestamp(json?['lastScan']),
      );

  final int songs;
  final int albums;
  final int artists;
  final int genres;
  final int playlists;
  final int users;

  /// Durée cumulée de tous les titres, en secondes.
  final int duration;
  final DateTime? lastScan;
}

class ServerSystemInfo {
  const ServerSystemInfo({
    required this.php,
    required this.server,
    required this.os,
    required this.kernel,
    required this.load,
    required this.time,
    required this.timezone,
    this.cpus,
    this.memTotal,
    this.memFree,
    this.uptime,
  });

  factory ServerSystemInfo.fromJson(Map<String, dynamic>? json) =>
      ServerSystemInfo(
        php: json?['php'] as String? ?? '',
        server: json?['server'] as String? ?? '',
        os: json?['os'] as String? ?? '',
        kernel: json?['kernel'] as String? ?? '',
        cpus: (json?['cpus'] as num?)?.toInt(),
        load: (json?['load'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        memTotal: (json?['memTotal'] as num?)?.toInt(),
        memFree: (json?['memFree'] as num?)?.toInt(),
        uptime: (json?['uptime'] as num?) == null
            ? null
            : Duration(seconds: (json!['uptime'] as num).toInt()),
        time: json?['time'] as String? ?? '',
        timezone: json?['timezone'] as String? ?? '',
      );

  final String php;
  final String server;
  final String os;
  final String kernel;
  final int? cpus;

  /// Charge moyenne sur 1, 5 et 15 minutes (vide si indisponible).
  final List<double> load;
  final int? memTotal;
  final int? memFree;
  final Duration? uptime;

  /// Heure du serveur déjà formatée dans son propre fuseau (« 04/08 02:18 »).
  final String time;
  final String timezone;
}

class ServerInfo {
  const ServerInfo({
    required this.disks,
    required this.music,
    required this.data,
    required this.library,
    required this.databaseBytes,
    required this.databaseName,
    required this.system,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    final db = json['database'] as Map<String, dynamic>?;
    return ServerInfo(
      disks: (json['disks'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(ServerDisk.fromJson)
          .toList(),
      music: ServerFolderSize.fromJson(json['music'] as Map<String, dynamic>?),
      data: ServerFolderSize.fromJson(json['data'] as Map<String, dynamic>?),
      library:
          ServerLibraryInfo.fromJson(json['library'] as Map<String, dynamic>?),
      databaseBytes: (db?['bytes'] as num?)?.toInt() ?? 0,
      databaseName: db?['name'] as String? ?? '',
      system: ServerSystemInfo.fromJson(json['system'] as Map<String, dynamic>?),
    );
  }

  final List<ServerDisk> disks;
  final ServerFolderSize music;
  final ServerFolderSize data;
  final ServerLibraryInfo library;
  final int databaseBytes;
  final String databaseName;
  final ServerSystemInfo system;
}

/// Horodatage Unix (secondes) du serveur → DateTime local.
DateTime? _timestamp(dynamic value) {
  final seconds = (value as num?)?.toInt();
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

class ServerInfoRepository {
  ServerInfoRepository(this._client);

  final ApiClient _client;

  Future<ServerInfo> info() async =>
      ServerInfo.fromJson(await _client.get('server-info.php') as Map<String, dynamic>);
}

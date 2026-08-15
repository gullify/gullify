import 'package:dio/dio.dart';

/// Error thrown for any failed API v2 call (business error, auth or network).
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  bool get isUnauthenticated => code == 'unauthenticated' || statusCode == 401;

  @override
  String toString() => 'ApiException($code): $message';
}

/// Thin client for the Gullify API v2.
///
/// Every endpoint returns the envelope `{success, data, error:{code,message}}`.
/// [get] and [post] unwrap it: they return `data` or throw [ApiException].
class ApiClient {
  ApiClient({required String serverUrl, String? token})
      : _token = token, // ignore: prefer_initializing_formals
        _dio = Dio(
          BaseOptions(
            baseUrl: '${_normalize(serverUrl)}/api/v2/',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            // Always parse the body ourselves — the envelope carries the error.
            validateStatus: (_) => true,
            responseType: ResponseType.json,
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final t = _token;
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  String? _token;

  String serverUrl() =>
      _dio.options.baseUrl.replaceFirst(RegExp(r'/api/v2/$'), '');

  // ignore: use_setters_to_change_properties
  void setToken(String? token) => _token = token;

  static String _normalize(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    try {
      return _unwrap(await _dio.get<dynamic>(path, queryParameters: query));
    } on DioException catch (e) {
      throw ApiException('network', e.message ?? 'Network error');
    }
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? form,
    Map<String, dynamic>? query,
  }) async {
    try {
      return _unwrap(
        await _dio.post<dynamic>(
          path,
          data: form ?? body,
          queryParameters: query,
          options: form != null
              ? Options(contentType: Headers.formUrlEncodedContentType)
              : null,
        ),
      );
    } on DioException catch (e) {
      throw ApiException('network', e.message ?? 'Network error');
    }
  }

  dynamic _unwrap(Response<dynamic> r) {
    final body = r.data;
    if (body is! Map<String, dynamic>) {
      throw ApiException(
        'bad_response',
        'Unexpected response from server (HTTP ${r.statusCode})',
        statusCode: r.statusCode,
      );
    }
    if (body['success'] == true) return body['data'];
    final err = body['error'];
    final code = err is Map ? (err['code'] as String? ?? 'unknown') : 'unknown';
    final message =
        err is Map ? (err['message'] as String? ?? 'Unknown error') : 'Unknown error';
    throw ApiException(code, message, statusCode: r.statusCode);
  }

  /// Absolute URL for a resource served by the legacy endpoints
  /// (images, streams) which live at the server root, not under /api/v2.
  String resourceUrl(String relative) => '${serverUrl()}/$relative';

  /// Envoie un logo de radio (URL distante re-hébergée, ou fichier local) à
  /// `upload_radio_logo.php` (racine, hors v2). Renvoie l'URL absolue servie.
  Future<String> uploadRadioLogo({String? imageUrl, String? filePath}) async {
    final form = FormData();
    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      form.fields.add(MapEntry('url', imageUrl.trim()));
    } else if (filePath != null) {
      final ext = filePath.split('.').last.toLowerCase();
      final subtype = ext == 'png'
          ? 'png'
          : ext == 'webp'
              ? 'webp'
              : 'jpeg';
      form.files.add(MapEntry(
        'logo',
        await MultipartFile.fromFile(
          filePath,
          contentType: DioMediaType('image', subtype),
        ),
      ));
    } else {
      throw ApiException('upload', 'Aucune image fournie');
    }
    final r = await _dio.post<dynamic>(
      '${serverUrl()}/upload_radio_logo.php',
      data: form,
    );
    final body = r.data;
    if (body is Map && body['error'] != true && body['url'] != null) {
      final u = body['url'] as String;
      return u.startsWith('http') ? u : '${serverUrl()}$u';
    }
    throw ApiException(
      'upload',
      (body is Map ? body['message'] as String? : null) ?? "Échec de l'upload",
    );
  }

  /// Téléverse une photo de profil (`profile.php?action=set_avatar`).
  /// Renvoie l'URL relative servie (ex. `serve_avatar.php?user_id=…`).
  Future<String?> uploadAvatar(String filePath) async {
    final ext = filePath.split('.').last.toLowerCase();
    final subtype = ext == 'png'
        ? 'png'
        : ext == 'webp'
            ? 'webp'
            : 'jpeg';
    final form = FormData();
    form.files.add(MapEntry(
      'avatar',
      await MultipartFile.fromFile(
        filePath,
        contentType: DioMediaType('image', subtype),
      ),
    ));
    final data = await post(
      'profile.php',
      body: form,
      query: {'action': 'set_avatar'},
    ) as Map<String, dynamic>;
    return data['avatarUrl'] as String?;
  }

  /// Supprime la photo de profil de l'utilisateur courant.
  Future<void> removeAvatar() =>
      post('profile.php', query: {'action': 'remove_avatar'});

  /// Envoie une image du téléphone comme photo d'un artiste (idée #78).
  /// Renvoie ce que le serveur répond (`artist_id`, `imageUrl`, `version`).
  Future<Map<String, dynamic>> uploadArtistImage(
    int artistId,
    String filePath,
  ) =>
      _uploadImage('set_artist_image', 'artist_id', artistId, filePath);

  /// Envoie une image du téléphone comme jaquette d'un album (idée #93).
  /// Renvoie ce que le serveur répond (`album_id`, `artworkUrl`, `version`).
  Future<Map<String, dynamic>> uploadAlbumCover(
    int albumId,
    String filePath,
  ) =>
      _uploadImage('set_album_cover', 'album_id', albumId, filePath);

  /// Le téléversement d'une image de bibliothèque : photo d'artiste ou
  /// jaquette d'album, même formulaire à un champ et un fichier.
  Future<Map<String, dynamic>> _uploadImage(
    String action,
    String idField,
    int id,
    String filePath,
  ) async {
    final ext = filePath.split('.').last.toLowerCase();
    final subtype = ext == 'png'
        ? 'png'
        : ext == 'webp'
            ? 'webp'
            : 'jpeg';
    final form = FormData();
    form.fields.add(MapEntry(idField, '$id'));
    form.files.add(MapEntry(
      'image',
      await MultipartFile.fromFile(
        filePath,
        contentType: DioMediaType('image', subtype),
      ),
    ));
    final data = await post(
      'library.php',
      body: form,
      query: {'action': action},
    );
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }
}

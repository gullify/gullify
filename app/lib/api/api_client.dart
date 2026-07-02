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
    Map<String, dynamic>? query,
  }) async {
    try {
      return _unwrap(
        await _dio.post<dynamic>(path, data: body, queryParameters: query),
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
}

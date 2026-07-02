import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../models/user.dart';

const _storage = FlutterSecureStorage();
const _kServerUrl = 'gullify_server_url';
const _kToken = 'gullify_token';

enum AuthStatus { unknown, needsServer, needsLogin, authenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.serverUrl,
    this.token,
    this.user,
  });

  final AuthStatus status;
  final String? serverUrl;
  final String? token;
  final User? user;

  AuthState copyWith({
    AuthStatus? status,
    String? serverUrl,
    String? token,
    User? user,
  }) =>
      AuthState(
        status: status ?? this.status,
        serverUrl: serverUrl ?? this.serverUrl,
        token: token ?? this.token,
        user: user ?? this.user,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return const AuthState();
  }

  /// Quoi qu'il arrive, le splash doit avancer : toute erreur inattendue
  /// (stockage sécurisé, réseau, réponse malformée, timeout) retombe sur
  /// l'écran de connexion ou de serveur — jamais sur un blocage.
  Future<void> _restore() async {
    String? serverUrl;
    String? token;
    try {
      serverUrl = await _storage.read(key: _kServerUrl)
          .timeout(const Duration(seconds: 10));
      token = await _storage.read(key: _kToken)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      state = const AuthState(status: AuthStatus.needsServer);
      return;
    }

    if (serverUrl == null || serverUrl.isEmpty) {
      state = const AuthState(status: AuthStatus.needsServer);
      return;
    }
    if (token == null || token.isEmpty) {
      state = AuthState(status: AuthStatus.needsLogin, serverUrl: serverUrl);
      return;
    }

    final client = ApiClient(serverUrl: serverUrl, token: token);
    try {
      final data = await client
          .get('auth.php', query: {'action': 'me'})
          .timeout(const Duration(seconds: 15));
      final user = User.fromJson(
        (data as Map<String, dynamic>)['user'] as Map<String, dynamic>,
      );
      state = AuthState(
        status: AuthStatus.authenticated,
        serverUrl: serverUrl,
        token: token,
        user: user,
      );
    } on ApiException catch (e) {
      if (e.isUnauthenticated) {
        await _storage.delete(key: _kToken);
      }
      // Sinon : serveur injoignable — on garde les identifiants et
      // l'utilisateur pourra réessayer depuis l'écran de connexion.
      state = AuthState(status: AuthStatus.needsLogin, serverUrl: serverUrl);
    } catch (_) {
      state = AuthState(status: AuthStatus.needsLogin, serverUrl: serverUrl);
    }
  }

  /// Validates the server by hitting /api/v2/ping.php, then stores it.
  Future<void> setServer(String url) async {
    final client = ApiClient(serverUrl: url);
    final data = await client.get('ping.php');
    if (data is! Map || data['server'] != 'Gullify') {
      throw ApiException('not_gullify', 'This server does not look like a Gullify server');
    }
    final normalized = client.serverUrl();
    await _storage.write(key: _kServerUrl, value: normalized);
    state = AuthState(status: AuthStatus.needsLogin, serverUrl: normalized);
  }

  Future<void> login(String username, String password) async {
    final serverUrl = state.serverUrl!;
    final client = ApiClient(serverUrl: serverUrl);
    final data = await client.post(
      'auth.php',
      query: {'action': 'login'},
      body: {'username': username, 'password': password},
    ) as Map<String, dynamic>;

    final token = data['token'] as String;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    await _storage.write(key: _kToken, value: token);
    state = AuthState(
      status: AuthStatus.authenticated,
      serverUrl: serverUrl,
      token: token,
      user: user,
    );
  }

  Future<void> logout() async {
    final s = state;
    if (s.token != null && s.serverUrl != null) {
      try {
        await ApiClient(serverUrl: s.serverUrl!, token: s.token)
            .post('auth.php', query: {'action': 'logout'});
      } catch (_) {
        // Best effort — clear local state regardless.
      }
    }
    await _storage.delete(key: _kToken);
    state = AuthState(status: AuthStatus.needsLogin, serverUrl: s.serverUrl);
  }

  Future<void> changeServer() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kServerUrl);
    state = const AuthState(status: AuthStatus.needsServer);
  }
}

final authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Authenticated API client. Only valid when status == authenticated.
final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authProvider);
  if (auth.serverUrl == null) {
    throw StateError('apiClientProvider read before server configuration');
  }
  return ApiClient(serverUrl: auth.serverUrl!, token: auth.token);
});

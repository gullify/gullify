import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/party_repository.dart';
import 'auth.dart';

final partyRepositoryProvider = Provider<PartyRepository>(
  (ref) => PartyRepository(ref.watch(apiClientProvider)),
);

/// URL de lecture d'un morceau à partir de son seul chemin : une manche ne
/// transporte pas un `Song` complet, juste ce qu'il faut à l'hôte pour faire
/// sonner l'extrait.
final partyStreamUrlProvider = Provider<String Function(String)>((ref) {
  final client = ref.watch(apiClientProvider);
  return (path) =>
      client.resourceUrl('stream.php?path=${Uri.encodeQueryComponent(path)}');
});

/// Ce que l'app sait de la partie en cours côté hôte.
class PartySession {
  const PartySession({
    this.code,
    this.token,
    this.shareUrl,
    this.state,
    this.error,
    this.busy = false,
  });

  final String? code;
  final String? token;

  /// Le lien à envoyer par SMS.
  final String? shareUrl;
  final PartyState? state;
  final String? error;

  /// Une action est en vol (création, lancement…).
  final bool busy;

  bool get active => code != null && token != null;

  PartySession copyWith({
    String? code,
    String? token,
    String? shareUrl,
    PartyState? state,
    String? error,
    bool? busy,
    bool clearError = false,
  }) =>
      PartySession(
        code: code ?? this.code,
        token: token ?? this.token,
        shareUrl: shareUrl ?? this.shareUrl,
        state: state ?? this.state,
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
      );
}

/// Pilote la partie côté hôte : création du salon, sondage régulier de l'état
/// et envoi des réponses.
///
/// Le sondage est aussi ce qui fait avancer les manches côté serveur (il n'y a
/// pas de tâche de fond) : tant que l'écran est ouvert, la partie vit.
class PartyController extends Notifier<PartySession> {
  Timer? _poll;
  bool _fetching = false;

  @override
  PartySession build() {
    ref.onDispose(_stopPolling);
    return const PartySession();
  }

  PartyRepository get _repo => ref.read(partyRepositoryProvider);

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 800), (_) => refresh());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  String _messageOf(Object e) =>
      e is ApiException ? e.message : 'Connexion au serveur impossible';

  /// Crée un salon et commence à le suivre.
  Future<bool> create({required String game, required String audioMode}) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final ticket = await _repo.create(game: game, audioMode: audioMode);
      state = PartySession(
        code: ticket.code,
        token: ticket.token,
        shareUrl: ticket.url,
        state: ticket.state,
      );
      _startPolling();
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: _messageOf(e));
      return false;
    }
  }

  Future<void> refresh() async {
    final code = state.code, token = state.token;
    if (code == null || token == null || _fetching) return;
    _fetching = true;
    try {
      state = state.copyWith(state: await _repo.state(code, token), clearError: true);
    } catch (e) {
      // Le salon a disparu (fermé, expiré) : on rend la main proprement.
      if (e is ApiException &&
          (e.code == 'party_not_found' || e.code == 'player_not_found')) {
        _stopPolling();
        state = PartySession(error: e.message);
      }
      // Une coupure réseau passagère ne doit pas casser la partie : on
      // retentera au prochain tour.
    } finally {
      _fetching = false;
    }
  }

  Future<void> start() async {
    final code = state.code, token = state.token;
    if (code == null || token == null) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      state = state.copyWith(state: await _repo.start(code, token), busy: false);
    } catch (e) {
      state = state.copyWith(busy: false, error: _messageOf(e));
    }
  }

  Future<void> answer(String answer) async {
    final code = state.code, token = state.token;
    if (code == null || token == null) return;
    final current = state.state;
    if (current == null || current.phase != 'guessing') return;
    try {
      state = state.copyWith(state: await _repo.answer(code, token, answer));
    } catch (e) {
      state = state.copyWith(error: _messageOf(e));
    }
  }

  Future<void> skip() async {
    final code = state.code, token = state.token;
    if (code == null || token == null) return;
    try {
      state = state.copyWith(state: await _repo.skip(code, token));
    } catch (e) {
      state = state.copyWith(error: _messageOf(e));
    }
  }

  /// Ferme le salon et oublie la partie — le lien SMS ne répond plus.
  Future<void> close() async {
    final code = state.code, token = state.token;
    _stopPolling();
    state = const PartySession();
    if (code == null || token == null) return;
    try {
      await _repo.close(code, token);
    } catch (_) {
      // Le salon expirera de lui-même : inutile d'embêter l'utilisateur.
    }
  }
}

final partyProvider = NotifierProvider<PartyController, PartySession>(
  PartyController.new,
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../state/auth.dart';
import '../../state/tv_log.dart';
import 'tv_kit.dart';
import 'tv_text_entry.dart';

/// Les deux écrans d'entrée, version téléviseur : adresse du serveur, puis
/// identifiants. Ils reprennent exactement la logique des écrans tactiles —
/// seule la saisie change, parce que taper à la télécommande n'a rien à voir
/// avec taper au doigt (voir [TvTextEntry]).

class TvServerScreen extends ConsumerStatefulWidget {
  const TvServerScreen({super.key});

  @override
  ConsumerState<TvServerScreen> createState() => _TvServerScreenState();
}

class _TvServerScreenState extends ConsumerState<TvServerScreen> {
  /// Pré-rempli : personne n'a envie de taper « https:// » lettre par lettre.
  String _url = 'https://';
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    final url = _url.trim();
    // Une adresse réduite au préfixe ne mène nulle part : le dire plutôt que
    // de laisser le bouton paraître mort.
    if (url.isEmpty || url == 'https://' || url == 'http://') {
      setState(() => _error = 'Saisis l\'adresse de ton serveur.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    TvLog.add('connexion au serveur $url');
    try {
      await ref.read(authProvider.notifier).setServer(url);
      TvLog.add('serveur accepté');
    } on ApiException catch (e) {
      TvLog.add('serveur refusé : ${e.code} ${e.message}');
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      TvLog.add('serveur injoignable : $e');
      if (mounted) setState(() => _error = 'Impossible de joindre le serveur');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ConnectFrame(
      title: 'Ton serveur Gullify',
      subtitle:
          'Saisis l\'adresse avec la croix directionnelle : « OK » tape la '
          'lettre visée.',
      error: _error,
      busy: _busy,
      child: TvTextEntry(
        fields: [TvEntryField(label: 'ADRESSE', value: _url)],
        active: 0,
        onSelectField: (_) {},
        onType: (c) => setState(() => _url += c),
        onBackspace: () => setState(() {
          if (_url.isNotEmpty) _url = _url.substring(0, _url.length - 1);
        }),
        onSubmit: _connect,
        submitLabel: _busy ? 'Connexion…' : 'Se connecter',
        submitEnabled: !_busy,
      ),
    );
  }
}

class TvLoginScreen extends ConsumerStatefulWidget {
  const TvLoginScreen({super.key});

  @override
  ConsumerState<TvLoginScreen> createState() => _TvLoginScreenState();
}

class _TvLoginScreenState extends ConsumerState<TvLoginScreen> {
  final _values = <String>['', ''];
  int _active = 0;
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    final username = _values[0].trim();
    final password = _values[1];
    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _error = 'Il faut un nom d\'utilisateur et un mot de passe.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    TvLog.add('connexion de $username');
    try {
      await ref.read(authProvider.notifier).login(username, password);
      TvLog.add('connecté');
    } on ApiException catch (e) {
      TvLog.add('connexion refusée : ${e.code}');
      if (mounted) {
        setState(
          () => _error = e.code == 'invalid_credentials'
              ? 'Identifiants invalides'
              : e.message,
        );
      }
    } catch (e) {
      TvLog.add('connexion impossible : $e');
      if (mounted) setState(() => _error = 'Connexion au serveur impossible');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(authProvider).serverUrl ?? '';
    return _ConnectFrame(
      title: 'Connexion',
      subtitle: server.isEmpty
          ? 'Choisis un champ, puis tape avec la croix directionnelle.'
          : 'Sur $server — choisis un champ, puis tape avec la croix.',
      error: _error,
      busy: _busy,
      child: TvTextEntry(
        fields: [
          TvEntryField(label: 'UTILISATEUR', value: _values[0]),
          TvEntryField(label: 'MOT DE PASSE', value: _values[1], obscure: true),
        ],
        active: _active,
        onSelectField: (i) => setState(() => _active = i),
        onType: (c) => setState(() => _values[_active] += c),
        onBackspace: () => setState(() {
          final v = _values[_active];
          if (v.isNotEmpty) _values[_active] = v.substring(0, v.length - 1);
        }),
        onSubmit: _login,
        submitLabel: _busy ? 'Connexion…' : 'Se connecter',
        submitEnabled: !_busy,
        symbols: const ['.', '-', '_', '@', '!', '?'],
      ),
    );
  }
}

/// La coque commune : mascotte, titre, la saisie, et l'erreur éventuelle.
class _ConnectFrame extends StatelessWidget {
  const _ConnectFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.busy,
    this.error,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvScaffold(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/icon/mascot.png', width: 150, height: 150),
                const SizedBox(height: 20),
                TvTitle(title),
                const SizedBox(height: 14),
                SizedBox(
                  width: 560,
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 26),
                  const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 26),
                  SizedBox(
                    width: 560,
                    child: Text(
                      error!,
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: scheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 60),
          SizedBox(width: 760, child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }
}

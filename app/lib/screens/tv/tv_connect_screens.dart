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
/// avec taper au doigt (voir [TvImeField]).

class TvServerScreen extends ConsumerStatefulWidget {
  const TvServerScreen({super.key});

  @override
  ConsumerState<TvServerScreen> createState() => _TvServerScreenState();
}

class _TvServerScreenState extends ConsumerState<TvServerScreen> {
  /// Pré-rempli : personne n'a envie de taper « https:// » lettre par lettre.
  final _url = TextEditingController(text: 'https://');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _url.text.trim();
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
      subtitle: 'Appuie sur OK pour ouvrir le clavier de la télé.',
      error: _error,
      busy: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TvImeField(
            label: 'ADRESSE DU SERVEUR',
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            onSubmitted: _connect,
          ),
          const SizedBox(height: 26),
          TvPill(
            label: _busy ? 'Connexion…' : 'Se connecter',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: _busy ? null : _connect,
          ),
        ],
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
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _user.text.trim();
    final password = _pass.text;
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
          ? 'Appuie sur OK sur un champ pour ouvrir le clavier.'
          : 'Sur $server — appuie sur OK sur un champ pour ouvrir le clavier.',
      error: _error,
      busy: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TvImeField(
            label: 'NOM D\'UTILISATEUR',
            controller: _user,
            autofocus: true,
            onSubmitted: () => FocusScope.of(context).nextFocus(),
          ),
          const SizedBox(height: 16),
          TvImeField(
            label: 'MOT DE PASSE',
            controller: _pass,
            obscure: true,
            onSubmitted: _login,
          ),
          const SizedBox(height: 26),
          TvPill(
            label: _busy ? 'Connexion…' : 'Se connecter',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: _busy ? null : _login,
          ),
        ],
      ),
    );
  }
}

/// La coque commune : la mascotte, le titre, la saisie — centrés, dans une
/// colonne étroite.
///
/// Volontairement proche de l'écran du téléphone plutôt qu'étalé sur toute la
/// largeur : sur un téléviseur, un formulaire de trois lignes n'a aucune
/// raison d'occuper deux mètres de diagonale, et le regard n'a alors plus
/// rien à suivre. Les tailles restent au-dessus du plancher des dix pieds.
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
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/icon/mascot.png', width: 108, height: 108),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 23,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 30),
                child,
                if (busy) ...[
                  const SizedBox(height: 22),
                  const Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

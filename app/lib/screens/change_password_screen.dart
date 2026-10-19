import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../state/auth.dart';
import '../widgets/wordmark.dart';

/// « Choisis ton nouveau mot de passe » : le mot de passe reçu de la personne
/// qui gère la maison est temporaire. Tant qu'il n'est pas changé, l'app ne
/// montre rien d'autre (voir AuthStatus.mustChangePassword).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _ancien = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _ancien.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final ancien = _ancien.text;
    final nouveau = _nouveau.text;
    String? erreur;
    if (ancien.isEmpty) {
      erreur = 'Entre le mot de passe que tu as reçu.';
    } else if (nouveau.length < 8) {
      erreur = 'Le nouveau mot de passe doit faire au moins 8 caractères.';
    } else if (nouveau != _confirmation.text) {
      erreur = 'Les deux mots de passe ne sont pas pareils.';
    } else if (nouveau == ancien) {
      erreur = "Le nouveau mot de passe doit être différent de l'ancien.";
    }
    if (erreur != null) {
      setState(() => _error = erreur);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).changePassword(ancien, nouveau);
    } on ApiException catch (e) {
      if (e.isUnauthenticated) {
        await ref.read(authProvider.notifier).logout();
        return;
      }
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Connexion au serveur impossible');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _champ(String label) => InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: GulliLogo(fontSize: 34)),
                  const SizedBox(height: 18),
                  Text(
                    'Choisis ton nouveau mot de passe',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Le mot de passe que tu as reçu${user != null ? ' pour « ${user.username} »' : ''} '
                    "est temporaire. Choisis-en un à toi pour continuer.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _ancien,
                    obscureText: _obscure,
                    autocorrect: false,
                    decoration: _champ('Mot de passe reçu'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nouveau,
                    obscureText: _obscure,
                    autocorrect: false,
                    decoration: _champ('Nouveau mot de passe (8 caractères au moins)'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmation,
                    obscureText: _obscure,
                    autocorrect: false,
                    decoration: _champ('Encore une fois'),
                    onSubmitted: (_) => _valider(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _valider,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Enregistrer'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => ref.read(authProvider.notifier).logout(),
                    child: const Text('Se déconnecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

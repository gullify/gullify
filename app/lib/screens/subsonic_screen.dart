import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../state/auth.dart';

/// Paramètres → Clients Subsonic (comptes de la maison seulement).
///
/// Les clients Subsonic (DSub, Symfonium, Ultrasonic…) ne peuvent pas utiliser
/// le mot de passe de la maison : le protocole exige que le serveur connaisse
/// le mot de passe en clair. On leur donne donc un « mot de passe
/// d'application » propre à GulliFY, montré UNE seule fois, révocable.
class SubsonicScreen extends ConsumerStatefulWidget {
  const SubsonicScreen({super.key});

  @override
  ConsumerState<SubsonicScreen> createState() => _SubsonicScreenState();
}

class _SubsonicScreenState extends ConsumerState<SubsonicScreen> {
  bool? _actif;
  String? _identifiant;

  /// Le mot de passe tout juste créé — gardé en mémoire le temps de l'écran.
  String? _nouveau;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _appeler(Future<dynamic> Function(ApiClient c) f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await f(ref.read(apiClientProvider));
      if (data is Map) {
        setState(() {
          _actif = data['actif'] == true;
          _identifiant = data['identifiant'] as String? ?? _identifiant;
          _nouveau = data['motDePasse'] as String?;
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Connexion au serveur impossible');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _charger() =>
      _appeler((c) => c.get('auth.php', query: {'action': 'subsonic'}));

  Future<void> _generer() async {
    if (_actif == true) {
      final ok = await _confirmer(
        'Créer un nouveau mot de passe ?',
        "L'ancien cessera de marcher : les clients Subsonic déjà réglés "
            'devront recevoir le nouveau.',
      );
      if (!ok) return;
    }
    await _appeler(
      (c) => c.post('auth.php', query: {'action': 'subsonic_generer'}),
    );
  }

  Future<void> _revoquer() async {
    final ok = await _confirmer(
      'Révoquer le mot de passe ?',
      'Les clients Subsonic réglés avec lui ne pourront plus se connecter.',
    );
    if (!ok) return;
    await _appeler(
      (c) => c.post('auth.php', query: {'action': 'subsonic_revoquer'}),
    );
  }

  Future<bool> _confirmer(String titre, String texte) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titre),
          content: Text(texte),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuer'),
            ),
          ],
        ),
      ) ??
      false;

  void _copier(String texte, String quoi) {
    Clipboard.setData(ClipboardData(text: texte));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$quoi copié')));
  }

  Widget _ligne(String titre, String valeur, {bool copier = true}) => ListTile(
        title: Text(titre),
        subtitle: SelectableText(valeur),
        trailing: copier
            ? IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copier',
                onPressed: () => _copier(valeur, titre),
              )
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serveur = ref.watch(authProvider).serverUrl ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Clients Subsonic')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Les apps Subsonic (DSub, Symfonium, Ultrasonic…) ne peuvent '
              'pas utiliser le mot de passe de la maison. Crée-leur un mot de '
              "passe d'application : il n'ouvre que GulliFY, et tu peux le "
              'révoquer à tout moment.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          _ligne('Adresse du serveur', serveur),
          if (_identifiant != null) _ligne("Nom d'utilisateur", _identifiant!),
          if (_nouveau != null)
            Card(
              margin: const EdgeInsets.all(16),
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ton mot de passe d\'application',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _nouveau!,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copier',
                          onPressed: () =>
                              _copier(_nouveau!, 'Mot de passe'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Note-le maintenant : il ne sera plus jamais montré. "
                      'Perdu ? Crées-en un nouveau.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          else if (_actif != null)
            ListTile(
              leading: Icon(
                _actif! ? Icons.check_circle_outline : Icons.block,
              ),
              title: Text(
                _actif!
                    ? "Un mot de passe d'application est actif"
                    : "Aucun mot de passe d'application",
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _busy || _actif == null ? null : _generer,
                  icon: const Icon(Icons.key),
                  label: Text(
                    _actif == true
                        ? 'Créer un nouveau mot de passe'
                        : "Créer un mot de passe d'application",
                  ),
                ),
                if (_actif == true) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _revoquer,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Révoquer'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

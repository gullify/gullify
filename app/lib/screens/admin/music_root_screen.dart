import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/music_root_repository.dart';
import '../../state/music_root.dart';
import '../../state/server_update.dart';

/// Choisir où est la musique, sur la machine.
///
/// Ce n'est pas un réglage comme un autre : c'est le dossier que Docker monte
/// sous les pieds du serveur. Le conteneur ne voit rien d'autre que ce qu'on
/// lui a déjà monté — c'est donc le compagnon, dehors, qui regarde les
/// disques, puis qui remonte la pile une fois le choix fait.
class MusicRootScreen extends ConsumerStatefulWidget {
  const MusicRootScreen({super.key});

  @override
  ConsumerState<MusicRootScreen> createState() => _MusicRootScreenState();
}

class _MusicRootScreenState extends ConsumerState<MusicRootScreen> {
  /// Vide = l'écran de départ (les disques, le dossier personnel).
  String _chemin = '';
  bool _envoi = false;

  void _ouvre(String chemin) => setState(() => _chemin = chemin);

  Future<void> _choisir(String chemin) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lire la musique ici ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chemin, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text(
              'Le serveur va redémarrer pour se remonter sur ce dossier — '
              'quelques secondes pendant lesquelles il ne répondra pas. '
              'Ensuite, lance une analyse de la bibliothèque pour y '
              'retrouver tes titres.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Changer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    setState(() => _envoi = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(musicRootRepositoryProvider).choisir(chemin);
      // Le serveur tombe aussitôt : c'est le journal du compagnon, sur la
      // carte « Mise à jour », qui raconte la suite.
      ref.invalidate(serverUpdateProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Le serveur se remonte sur ce dossier…')),
      );
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _envoi = false);
      messenger.showSnackBar(SnackBar(content: Text('Refusé : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vue = ref.watch(dossiersServeurProvider(_chemin));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dossier de musique'),
        bottom: _envoi
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: vue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icone: Icons.cloud_off,
          titre: 'Les dossiers ne se lisent pas',
          texte: '$e',
        ),
        data: (v) => _Liste(
          vue: v,
          surDossier: _ouvre,
          surRetour: v.depart
              ? null
              : () => _ouvre(v.parent == null || v.parent == v.chemin
                  ? ''
                  : v.parent!),
          surChoix: _envoi ? null : _choisir,
        ),
      ),
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({
    required this.vue,
    required this.surDossier,
    required this.surRetour,
    required this.surChoix,
  });

  final VueDossier vue;
  final void Function(String chemin) surDossier;
  final VoidCallback? surRetour;
  final void Function(String chemin)? surChoix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ici = vue.chemin;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vue.depart ? 'Les disques de la machine' : ici,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                vue.depart
                    ? 'Choisis où se trouve ta musique. Une clé USB ou un '
                        'disque externe apparaît ici une fois branché.'
                    : 'Le serveur lit actuellement ${vue.actuelle}',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (vue.erreur != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(vue.erreur!, style: TextStyle(color: scheme.error)),
          ),
        if (surRetour != null)
          ListTile(
            leading: const Icon(Icons.arrow_upward),
            title: const Text('Remonter'),
            onTap: surRetour,
          ),
        // Le dossier où l'on est fait un candidat aussi valable que ses
        // enfants : c'est souvent lui qu'on cherchait.
        if (!vue.depart && ici.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: surChoix == null ? null : () => surChoix!(ici),
              icon: const Icon(Icons.library_music),
              label: Text(
                vue.aDeLaMusique
                    ? 'Lire la musique ici'
                    : 'Lire la musique ici (rien trouvé en surface)',
              ),
            ),
          ),
        if (vue.tronque)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Beaucoup de dossiers ici : la liste est écourtée.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        if (vue.dossiers.isEmpty && !vue.depart)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text('Aucun sous-dossier.'),
          ),
        for (final d in vue.dossiers)
          ListTile(
            leading: Icon(
              d.aDeLaMusique ? Icons.library_music : Icons.folder_outlined,
              color: d.aDeLaMusique ? scheme.primary : null,
            ),
            title: Text(d.nom),
            subtitle: Text(
              d.aDeLaMusique ? '${d.chemin} · de la musique' : d.chemin,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => surDossier(d.chemin),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icone, required this.titre, required this.texte});

  final IconData icone;
  final String titre;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 42, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(titre,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              texte,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

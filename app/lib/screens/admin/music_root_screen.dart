import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
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
    // Chaque compte lit un sous-dossier de la racine : changer de racine sans
    // le dire, c'était chercher /media/musique/Maxime là où il n'y a qu'un
    // /media/musique plein de musique.
    final vue = ref.read(dossiersServeurProvider(_chemin)).value;
    final manquants = [
      for (final c in vue?.comptes ?? const <CompteMusique>[])
        if (vue!.trouve(c) == false) c,
    ];
    var aLaRacine = true;

    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Lire la musique ici ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chemin,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text(
                'Le serveur va redémarrer pour se remonter sur ce dossier — '
                'quelques secondes pendant lesquelles il ne répondra pas. '
                'Ensuite, lance une analyse de la bibliothèque pour y '
                'retrouver tes titres.',
              ),
              if (manquants.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  manquants.length == 1
                      ? '${manquants.single.nom} lit le dossier '
                          '« ${manquants.single.dossier} », qui n\'existe pas '
                          'ici.'
                      : '${manquants.map((c) => c.nom).join(', ')} lisent '
                          'des dossiers qui n\'existent pas ici.',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: aLaRacine,
                  onChanged: (v) => setDialog(() => aLaRacine = v ?? false),
                  title: Text(manquants.length == 1
                      ? 'Lui faire lire tout ce dossier'
                      : 'Leur faire lire tout ce dossier'),
                ),
              ],
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
      ),
    );
    if (confirme != true || !mounted) return;

    setState(() => _envoi = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(musicRootRepositoryProvider).choisir(
            chemin,
            aLaRacine: [if (aLaRacine) for (final c in manquants) c.id],
          );
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

  /// Un serveur d'avant la 1.3.0 n'a pas cette API : il répond par la page de
  /// l'app web, en HTTP 200, et l'app recevait « bad_response » — un mot qui
  /// n'apprend rien à qui doit décider quoi faire.
  bool _tropAncien(Object e) =>
      e is ApiException &&
      (e.code == 'bad_response' || e.statusCode == 404);

  String _explique(Object e) {
    if (_tropAncien(e)) {
      return 'Choisir le dossier de musique demande un serveur en 1.3.0 ou '
          'plus. Mets-le à jour depuis Infos du serveur, puis reviens ici.';
    }
    if (e is ApiException && e.code == 'compagnon_absent') return e.message;
    return '$e';
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
          icone: _tropAncien(e) ? Icons.update : Icons.cloud_off,
          titre: _tropAncien(e)
              ? 'Ce serveur ne sait pas encore faire ça'
              : 'Les dossiers ne se lisent pas',
          texte: _explique(e),
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
        // Ce que chaque compte lirait avec ce dossier pour racine : le sien
        // en dessous, qui doit exister ici.
        if (!vue.depart && ici.isNotEmpty && vue.comptes.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Avec ce dossier, les comptes liront',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final c in vue.comptes) _LigneCompte(compte: c, vue: vue),
          const Divider(height: 20),
        ],
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

class _LigneCompte extends StatelessWidget {
  const _LigneCompte({required this.compte, required this.vue});

  final CompteMusique compte;
  final VueDossier vue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trouve = vue.trouve(compte);
    final (icone, couleur, note) = switch (trouve) {
      true => (Icons.check_circle_outline, scheme.primary, null),
      false => (
          Icons.warning_amber_rounded,
          scheme.error,
          'Ce dossier n\'existe pas ici',
        ),
      null => (
          Icons.help_outline,
          scheme.onSurfaceVariant,
          compte.dossier == null ? 'Aucun dossier : ce compte ne lit rien' : null,
        ),
    };
    return ListTile(
      dense: true,
      leading: Icon(icone, color: couleur),
      title: Text(compte.nom),
      subtitle: Text(
        note == null ? compte.chemin(vue.chemin) : '${compte.chemin(vue.chemin)} · $note',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
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

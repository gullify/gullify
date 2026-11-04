import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/pour_toi_repository.dart';
import '../state/library.dart';
import '../state/pour_toi.dart';
import '../widgets/artwork.dart';

/// Accueil → Découvrir → « Artistes suggérés » : d'abord les artistes qu'on a
/// dit aimer dans « Tes artistes » sans les avoir encore dans la
/// bibliothèque, puis ceux que GulliFY propose (À découvrir ailleurs, les
/// proches des artistes choisis). Un toucher cherche l'artiste pour
/// l'écouter ou le télécharger ; le cœur l'ajoute à tes goûts.
class ArtistesSuggeresScreen extends ConsumerStatefulWidget {
  const ArtistesSuggeresScreen({super.key});

  @override
  ConsumerState<ArtistesSuggeresScreen> createState() =>
      _ArtistesSuggeresScreenState();
}

class _ArtistesSuggeresScreenState
    extends ConsumerState<ArtistesSuggeresScreen> {
  /// Ce qu'on vient d'aimer ou de retirer ici : clé → niveau.
  final _niveaux = <String, int>{};

  Future<void> _aimer(Bulle b) async {
    final avant = _niveaux[b.cle] ?? b.niveau;
    final apres = avant > 0 ? 0 : 1;
    setState(() => _niveaux[b.cle] = apres);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pourToiRepositoryProvider).choisir(b, apres);
    } catch (e) {
      if (!mounted) return;
      setState(() => _niveaux[b.cle] = avant);
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  void _chercher(String nom) {
    ref.read(searchQueryProvider.notifier).set(nom);
    context.go('/search');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suggestions = ref.watch(suggestionsArtistesProvider);
    Widget message(String texte) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artistes suggérés'),
        actions: [
          IconButton(
            tooltip: 'Tes artistes',
            icon: const Icon(Icons.bubble_chart_outlined),
            onPressed: () async {
              await context.push('/gouts/artistes');
              ref.invalidate(suggestionsArtistesProvider);
            },
          ),
        ],
      ),
      body: suggestions.hasError
          ? message(
              'Ton serveur ne connaît pas encore les artistes suggérés : '
              'mets-le à jour.',
            )
          : !suggestions.hasValue
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.refresh(suggestionsArtistesProvider.future),
              child: suggestions.value!.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 80),
                        message(
                          'Rien à proposer pour l\'instant. Dis à GulliFY qui '
                          'tu aimes dans Tes goûts → Tes artistes.',
                        ),
                      ],
                    )
                  : _Liste(
                      artistes: suggestions.value!,
                      niveaux: _niveaux,
                      onTap: _chercher,
                      onAimer: _aimer,
                    ),
            ),
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({
    required this.artistes,
    required this.niveaux,
    required this.onTap,
    required this.onAimer,
  });

  final List<ArtisteSuggere> artistes;
  final Map<String, int> niveaux;
  final void Function(String nom) onTap;
  final void Function(Bulle b) onAimer;

  @override
  Widget build(BuildContext context) {
    final gouts = [
      for (final a in artistes)
        if (a.dansTesGouts) a,
    ];
    final autres = [
      for (final a in artistes)
        if (!a.dansTesGouts) a,
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
      children: [
        if (gouts.isNotEmpty) ...[
          const _Titre(
            'Dans tes goûts, pas encore chez toi',
            'Tu les as aimés : il ne reste qu\'à les écouter ou les télécharger.',
          ),
          for (final a in gouts)
            _Ligne(a: a, niveaux: niveaux, onTap: onTap, onAimer: onAimer),
        ],
        if (autres.isNotEmpty) ...[
          const _Titre(
            'Suggérés pour toi',
            'D\'après ce que tu écoutes et les artistes que tu aimes.',
          ),
          for (final a in autres)
            _Ligne(a: a, niveaux: niveaux, onTap: onTap, onAimer: onAimer),
        ],
      ],
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.titre, this.sousTitre);

  final String titre;
  final String sousTitre;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          sousTitre,
          style: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.a,
    required this.niveaux,
    required this.onTap,
    required this.onAimer,
  });

  final ArtisteSuggere a;
  final Map<String, int> niveaux;
  final void Function(String nom) onTap;
  final void Function(Bulle b) onAimer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = a.bulle;
    final niveau = niveaux[b.cle] ?? b.niveau;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(20, 2, 8, 2),
      leading: Artwork(
        url: b.image,
        size: 52,
        borderRadius: 26,
        icon: Icons.person,
      ),
      title: Text(
        b.nom,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        a.raison,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      onTap: () => onTap(b.nom),
      trailing: IconButton(
        tooltip: niveau > 0 ? 'Retirer de tes goûts' : 'J\'aime',
        icon: Icon(
          niveau > 0 ? Icons.favorite : Icons.favorite_border,
          color: niveau > 0 ? scheme.primary : null,
        ),
        onPressed: () => onAimer(b),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/podcasts_repository.dart';
import '../state/podcasts.dart';
import '../widgets/album_card.dart' show kArtShadow;
import '../widgets/artwork.dart';
import '../widgets/glass_box.dart';
import '../widgets/glass_kit.dart';
import '../widgets/mascot_empty.dart';
import 'shell_screen.dart';

/// « Podcasts » (idée #112) : une recherche, ses abonnements, et un palmarès
/// par catégorie pour en découvrir.
///
/// Une série se comporte comme un artiste : on l'ouvre, on voit ses épisodes,
/// on en lance un — et la file continue avec les suivants.

/// Chemin de la fiche d'une série. L'adresse du flux voyage en paramètre :
/// c'est elle qui identifie une série d'un bout à l'autre.
String podcastShowPath(String feedUrl) =>
    '/podcasts/show?feed=${Uri.encodeQueryComponent(feedUrl)}';

class PodcastsScreen extends ConsumerStatefulWidget {
  const PodcastsScreen({super.key});

  @override
  ConsumerState<PodcastsScreen> createState() => _PodcastsScreenState();
}

class _PodcastsScreenState extends ConsumerState<PodcastsScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  /// La requête réellement envoyée : elle ne suit la frappe qu'après une
  /// pause, sinon chaque lettre interrogerait l'annuaire d'Apple.
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTyped(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _query = value.trim());
    });
    setState(() {}); // la croix « effacer » suit la frappe, elle
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Podcasts')),
      bottomNavigationBar: const DetailDock(),
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(podcastDiscoverProvider);
          return ref.refresh(podcastSubscriptionsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 16,
          ),
          children: [
            _SearchField(
              controller: _controller,
              onChanged: _onTyped,
              onClear: _controller.text.isEmpty ? null : _clear,
            ),
            const _FrenchOnlyChip(),
            if (searching)
              _SearchResults(query: _query)
            else ...[
              const _Subscriptions(),
              const _Discover(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Le champ de recherche, en verre comme celui des radios.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: GlassBox(
        radius: 16,
        blur: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.search, size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Chercher un podcast…',
                    isDense: true,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Francophone seulement » (idée #113) : la bascule vit au-dessus des deux
/// listes qu'elle filtre — la recherche et le palmarès.
class _FrenchOnlyChip extends ConsumerWidget {
  const _FrenchOnlyChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(podcastFrenchOnlyProvider);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: FilterChip(
          avatar: const Icon(Icons.translate, size: 18),
          label: const Text('Francophone seulement'),
          selected: on,
          onSelected: (value) =>
              ref.read(podcastFrenchOnlyProvider.notifier).set(value),
        ),
      ),
    );
  }
}

/// Ce que l'annuaire d'Apple rend pour la requête.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(podcastSearchProvider(query));
    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _Unreachable(
        onRetry: () => ref.invalidate(podcastSearchProvider(query)),
      ),
      data: (shows) => shows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: MascotEmpty(
                message: 'Aucun podcast trouvé',
                hint: ref.watch(podcastFrenchOnlyProvider)
                    // Le filtre écarte beaucoup : le dire vaut mieux que de
                    // laisser croire que l'annuaire ne connaît rien.
                    ? 'Rien de francophone pour cette recherche — essaie un '
                        'autre nom, ou décoche « Francophone seulement ».'
                    : 'Essaie le nom de la série, ou celui de qui l\'anime.',
              ),
            )
          : Column(
              children: [for (final s in shows) PodcastShowTile(show: s)],
            ),
    );
  }
}

/// « Mes abonnements » : un carrousel de pochettes, comme les albums.
class _Subscriptions extends ConsumerWidget {
  const _Subscriptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(podcastSubscriptionsProvider);
    return subs.when(
      loading: () => const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _Unreachable(
        onRetry: () => ref.invalidate(podcastSubscriptionsProvider),
      ),
      data: (shows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Mes abonnements',
            padding: EdgeInsets.fromLTRB(20, 10, 20, 8),
          ),
          if (shows.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Aucun abonnement pour l\'instant — cherche une série, ou '
                'pioche dans le palmarès plus bas.',
                style: TextStyle(fontSize: 13, height: 1.3),
              ),
            )
          else
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: shows.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _ShowCard(show: shows[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// « À découvrir » : le palmarès d'Apple, catégorie par catégorie.
class _Discover extends ConsumerWidget {
  const _Discover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(podcastGenresProvider);
    final chosen = ref.watch(podcastGenreChoiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          'À découvrir',
          padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
        ),
        SizedBox(
          height: 44,
          child: genres.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (list) => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              children: [
                for (final g in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(g.name),
                      selected: g.id == chosen,
                      onSelected: (_) => ref
                          .read(podcastGenreChoiceProvider.notifier)
                          .select(g.id),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        _DiscoverList(genreId: chosen),
      ],
    );
  }
}

class _DiscoverList extends ConsumerWidget {
  const _DiscoverList({required this.genreId});

  final int genreId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shows = ref.watch(podcastDiscoverProvider(genreId));
    return shows.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _Unreachable(
        onRetry: () => ref.invalidate(podcastDiscoverProvider(genreId)),
      ),
      data: (list) => list.isEmpty
          ? (ref.watch(podcastFrenchOnlyProvider)
              // Un palmarès sans francophone n'est pas un palmarès en panne.
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: MascotEmpty(
                    message: 'Rien de francophone ici',
                    hint: 'Cette catégorie ne classe aucune série en '
                        'français — essayes-en une autre, ou décoche '
                        '« Francophone seulement ».',
                  ),
                )
              : _Unreachable(
                  onRetry: () =>
                      ref.invalidate(podcastDiscoverProvider(genreId)),
                ))
          : Column(
              children: [
                for (var i = 0; i < list.length; i++)
                  PodcastShowTile(show: list[i], rank: i + 1),
              ],
            ),
    );
  }
}

/// Une série dans un carrousel : pochette carrée, nom et auteur dessous.
class _ShowCard extends StatelessWidget {
  const _ShowCard({required this.show});

  final PodcastShow show;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 128.0;
    return SizedBox(
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push(podcastShowPath(show.feedUrl), extra: show),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [kArtShadow],
              ),
              child: Artwork(
                url: show.image.isEmpty ? null : show.image,
                size: size,
                borderRadius: 20,
                icon: Icons.podcasts,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              show.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (show.author.isNotEmpty)
              Text(
                show.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rangée d'une série : pochette, nom, auteur — et de quoi s'abonner sans
/// quitter la liste.
class PodcastShowTile extends ConsumerWidget {
  const PodcastShowTile({super.key, required this.show, this.rank});

  final PodcastShow show;

  /// Rang dans un palmarès, affiché à la place de rien.
  final int? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (show.author.isNotEmpty) show.author,
      if (show.genre.isNotEmpty) show.genre,
    ].join(' · ');
    return ListTile(
      onTap: () => context.push(podcastShowPath(show.feedUrl), extra: show),
      contentPadding: const EdgeInsets.only(left: 16, right: 6),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rank != null)
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          Artwork(
            url: show.image.isEmpty ? null : show.image,
            size: 52,
            borderRadius: 10,
            icon: Icons.podcasts,
          ),
        ],
      ),
      title: Text(
        show.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: details.isEmpty
          ? null
          : Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PodcastSubscribeButton(show: show),
    );
  }
}

/// Le bouton d'abonnement : la même bascule partout (liste et fiche).
class PodcastSubscribeButton extends ConsumerStatefulWidget {
  const PodcastSubscribeButton({super.key, required this.show, this.wide = false});

  final PodcastShow show;

  /// Pilule avec texte (fiche de la série) plutôt qu'icône seule (liste).
  final bool wide;

  @override
  ConsumerState<PodcastSubscribeButton> createState() =>
      _PodcastSubscribeButtonState();
}

class _PodcastSubscribeButtonState
    extends ConsumerState<PodcastSubscribeButton> {
  bool _busy = false;

  /// L'abonnement tel qu'il est en base : la fiche reçue le dit, mais la liste
  /// des abonnements, elle, est la source de vérité — c'est ce qui garde le
  /// bouton juste d'un écran à l'autre.
  bool _subscribedIn(List<PodcastShow>? subs) => subs == null
      ? widget.show.subscribed
      : subs.any((s) => s.feedUrl == widget.show.feedUrl);

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final wasSubscribed =
        _subscribedIn(ref.read(podcastSubscriptionsProvider).value);
    try {
      final repo = ref.read(podcastsRepositoryProvider);
      if (wasSubscribed) {
        await repo.unsubscribe(widget.show.feedUrl);
      } else {
        await repo.subscribe(widget.show);
      }
      ref.invalidate(podcastSubscriptionsProvider);
      messenger.showSnackBar(SnackBar(
        content: Text(
          wasSubscribed
              ? 'Désabonné de « ${widget.show.title} »'
              : 'Abonné à « ${widget.show.title} »',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscribed =
        _subscribedIn(ref.watch(podcastSubscriptionsProvider).value);
    if (widget.wide) {
      return subscribed
          ? OutlinedButton.icon(
              onPressed: _busy ? null : _toggle,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Abonné'),
            )
          : FilledButton.icon(
              onPressed: _busy ? null : _toggle,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('S\'abonner'),
            );
    }
    return IconButton(
      tooltip: subscribed ? 'Se désabonner' : 'S\'abonner',
      icon: Icon(
        subscribed ? Icons.check_circle : Icons.add_circle_outline,
        color: subscribed ? Theme.of(context).colorScheme.primary : null,
      ),
      onPressed: _busy ? null : _toggle,
    );
  }
}

/// L'annuaire (ou le flux) n'a pas répondu.
class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: MascotEmpty(
          message: 'Rien à écouter pour l\'instant',
          hint: 'L\'annuaire des podcasts n\'a pas répondu. Vérifie la '
              'connexion, ou réessaie dans un instant.',
          action:
              TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ),
      );
}

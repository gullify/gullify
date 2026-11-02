import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/pour_toi_repository.dart';
import '../state/player.dart';
import '../state/pour_toi.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_box.dart';

/// « Tes goûts » : ce que GulliFY a compris, montré en clair — l'ADN
/// musical, les artistes repères, les habitudes, ce que la lecture
/// automatique a appris — et les leviers pour le corriger : le niveau
/// d'aventure, la lecture automatique, ce qu'on a écarté.
class GoutsScreen extends ConsumerWidget {
  const GoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profil = ref.watch(goutsProfilProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tes goûts'),
        actions: [
          IconButton(
            tooltip: 'Recalculer maintenant',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(pourToiRepositoryProvider).analyser();
                ref.invalidate(goutsProfilProvider);
                ref.invalidate(pourToiAccueilProvider);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Profil et mix recalculés.')),
                );
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
              }
            },
          ),
        ],
      ),
      body: profil.hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Ton serveur ne connaît pas encore « Pour toi » : mets-le à jour.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : !profil.hasValue
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.refresh(goutsProfilProvider.future),
              child: _Contenu(p: profil.value!),
            ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({required this.p});

  final GoutsProfil p;

  @override
  Widget build(BuildContext context) {
    final h = p.habitudes;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        _Portrait(p: p),
        if (p.etiquettes.isNotEmpty) ...[
          const _Titre('Ton ADN musical'),
          _Etiquettes(p: p),
        ],
        const _Titre('Tes artistes'),
        _TesArtistes(p: p),
        if (p.artistes.isNotEmpty) ...[
          const _Titre('Tes repères'),
          _Artistes(p: p),
        ],
        const _Titre('Tes 30 derniers jours'),
        _Habitudes(h: h),
        if (p.heures.any((x) => x > 0)) ...[
          const _Titre('Quand tu écoutes'),
          _Heures(heures: p.heures),
        ],
        if (p.reussite.isNotEmpty || p.appris.isNotEmpty) ...[
          const _Titre('Ce que GulliFY apprend'),
          _Apprentissage(p: p),
        ],
        const _Titre('Réglages'),
        _Reglages(p: p),
        if (p.rejets.isNotEmpty) ...[
          const _Titre('Écartés des suggestions'),
          _Rejets(p: p),
        ],
        const SizedBox(height: 16),
        _Sources(p: p),
      ],
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
    ),
  );
}

class _Carte extends StatelessWidget {
  const _Carte({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GlassBox(
    radius: 18,
    blur: false,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.p});

  final GoutsProfil p;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                p.profil.isEmpty ? 'Ton portrait' : 'Profil : ${p.profil}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(p.portrait, style: const TextStyle(fontSize: 15, height: 1.35)),
        ],
      ),
    );
  }
}

/// Une seule série (la part de chaque étiquette) : des barres de la couleur
/// d'accent, la valeur écrite au bout — pas de légende, le titre la nomme.
class _Etiquettes extends StatelessWidget {
  const _Etiquettes({required this.p});

  final GoutsProfil p;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tags = p.etiquettes;
    final max = tags
        .map((t) => t.part)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return _Carte(
      child: Column(
        children: [
          for (final t in tags)
            Semantics(
              label: '${t.nom}, ${(t.part * 100).round()} pour cent',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        t.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 10,
                            width: max <= 0 ? 0 : c.maxWidth * (t.part / max),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(t.part * 100).round()} %',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ce qu'on a dit aimer (les bulles), et la porte vers elles.
class _TesArtistes extends ConsumerWidget {
  const _TesArtistes({required this.p});

  final GoutsProfil p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final choix = p.choix;
    final adores = choix.where((c) => c.niveau >= 2).length;
    final aimes = choix.length - adores;
    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            choix.isEmpty
                ? 'Dis à GulliFY qui tu aimes : tes mix, ta lecture '
                    'automatique et tes découvertes partent de là.'
                : [
                    if (adores > 0) '$adores adoré${adores > 1 ? 's' : ''}',
                    if (aimes > 0) '$aimes aimé${aimes > 1 ? 's' : ''}',
                  ].join(' · '),
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
          if (choix.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in choix.take(12))
                  Chip(
                    avatar: Icon(
                      c.niveau >= 2 ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: scheme.primary,
                    ),
                    label: Text(c.nom),
                    visualDensity: VisualDensity.compact,
                  ),
                if (choix.length > 12)
                  Chip(
                    label: Text('+${choix.length - 12}'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () async {
              await context.push('/gouts/artistes');
              ref.invalidate(goutsProfilProvider);
            },
            icon: const Icon(Icons.bubble_chart_outlined),
            label: Text(choix.isEmpty ? 'Choisir mes artistes' : 'Modifier'),
          ),
        ],
      ),
    );
  }
}

class _Artistes extends StatelessWidget {
  const _Artistes({required this.p});

  final GoutsProfil p;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: p.artistes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final a = p.artistes[i];
          return SizedBox(
            width: 84,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/artist/${a.id}'),
              child: Column(
                children: [
                  Artwork(
                    url: a.imageUrl,
                    size: 72,
                    borderRadius: 36,
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a.nom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${a.ecoutes} écoutes',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _pct(Object? v) => v is num ? '${(v * 100).round()} %' : '—';

class _Habitudes extends StatelessWidget {
  const _Habitudes({required this.h});

  final Map<String, dynamic> h;

  @override
  Widget build(BuildContext context) {
    final minutes = (h['minutes'] as num?)?.toInt() ?? 0;
    final tiles = [
      ('${h['ecoutes'] ?? 0}', 'écoutes'),
      (minutes >= 120 ? '${minutes ~/ 60} h' : '$minutes min', 'de musique'),
      (_pct(h['tauxFini']), 'écoutés jusqu\'au bout'),
      (_pct(h['tauxSaute']), 'sautés avant 30 s'),
      ('${h['artistesEffectifs'] ?? 0}', 'artistes « effectifs »'),
      (
        h['nouveauxArtistes'] == null ? '—' : '${h['nouveauxArtistes']}',
        'nouveaux artistes',
      ),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.15,
      children: [for (final t in tiles) _Stat(valeur: t.$1, libelle: t.$2)],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.valeur, required this.libelle});

  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBox(
      radius: 16,
      blur: false,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              valeur,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              libelle,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.15,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les écoutes par heure (90 jours) : une série, des colonnes de la couleur
/// d'accent ; toucher une colonne dit son heure et son compte.
class _Heures extends StatelessWidget {
  const _Heures({required this.heures});

  final List<int> heures;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = heures.fold<int>(0, (a, b) => a > b ? a : b);
    final pic = heures.indexOf(max);
    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu écoutes surtout vers $pic h.',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 24; i++)
                  Expanded(
                    child: Tooltip(
                      message: '$i h : ${heures[i]} écoutes',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          height: max == 0 ? 0 : 2 + 70 * heures[i] / max,
                          decoration: BoxDecoration(
                            color: i == pic
                                ? scheme.primary
                                : scheme.primary.withValues(alpha: 0.45),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final l in ['0 h', '6 h', '12 h', '18 h', '23 h'])
                Text(
                  l,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Apprentissage extends StatelessWidget {
  const _Apprentissage({required this.p});

  final GoutsProfil p;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget ligne(String nom, String detail, double taux) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${(taux * 100).round()} %',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in p.reussite)
            ligne(
              r.nom,
              '${r.ecoutes} titres proposés · écoutés jusqu\'au bout',
              r.taux,
            ),
          if (p.appris.isNotEmpty) ...[
            if (p.reussite.isNotEmpty) const Divider(height: 20),
            Text(
              'La lecture automatique dose ses sources d\'après ce qui te réussit :',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            for (final a in p.appris)
              ligne(a.nom, '${a.essais} essais', a.taux),
          ],
        ],
      ),
    );
  }
}

class _Reglages extends ConsumerStatefulWidget {
  const _Reglages({required this.p});

  final GoutsProfil p;

  @override
  ConsumerState<_Reglages> createState() => _ReglagesState();
}

class _ReglagesState extends ConsumerState<_Reglages> {
  late double _aventure = widget.p.aventure;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final autoplay = ref.watch(autoplayProvider);
    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Niveau d\'aventure',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'Combien d\'inconnu dans tes mix, ta lecture automatique et tes radios.',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
          Slider(
            value: _aventure,
            divisions: 10,
            label: _aventure < 0.25
                ? 'Familier'
                : _aventure > 0.65
                ? 'Aventurier'
                : 'Équilibré',
            onChanged: (v) => setState(() => _aventure = v),
            onChangeEnd: (v) =>
                ref.read(pourToiRepositoryProvider).setAventure(v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ce que je connais',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              Text(
                'Fais-moi découvrir',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const Divider(height: 24),
          ListenableBuilder(
            listenable: autoplay,
            builder: (context, _) => Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: autoplay.enabled,
                onChanged: autoplay.setEnabled,
                title: const Text('Lecture automatique'),
                subtitle: const Text(
                  'Au bout de la file, la musique continue avec des titres proches.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rejets extends ConsumerStatefulWidget {
  const _Rejets({required this.p});

  final GoutsProfil p;

  @override
  ConsumerState<_Rejets> createState() => _RejetsState();
}

class _RejetsState extends ConsumerState<_Rejets> {
  final _retablis = <String>{};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rejets = [
      for (final r in widget.p.rejets)
        if (!_retablis.contains('${r.type}:${r.id}')) r,
    ];
    if (rejets.isEmpty) return const SizedBox.shrink();
    return _Carte(
      // Sa propre Material : sans elle, la vitre de la carte cacherait
      // l'effet du toucher sur les lignes.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final r in rejets)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r.type == 'artist'
                      ? Icons.person_off_outlined
                      : Icons.music_off_outlined,
                ),
                title: Text(
                  r.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  r.type == 'artist' ? 'Artiste' : (r.artiste ?? 'Titre'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    await ref
                        .read(pourToiRepositoryProvider)
                        .retablir(r.type, r.id);
                    setState(() => _retablis.add('${r.type}:${r.id}'));
                  },
                  child: const Text('Rétablir'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  const _Sources({required this.p});

  final GoutsProfil p;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = p.sources;
    final monde = s['monde'] == 'lastfm'
        ? 'Last.fm'
        : 'YouTube Music et MusicBrainz';
    final enrichis = s['enrichis'] ?? 0;
    final total = s['artistes'] ?? 0;
    return Text(
      'Analysé chaque nuit sur ton serveur, à partir de tes écoutes, sauts et favoris. '
      'Artistes proches : $monde ($enrichis sur $total de tes artistes déjà décrits).'
      '${s['ia'] == true ? ' Noms des mix et portrait : modèle de langue de ton serveur.' : ''}',
      style: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

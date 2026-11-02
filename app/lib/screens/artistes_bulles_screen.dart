import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/pour_toi_repository.dart';
import '../state/library.dart';
import '../state/pour_toi.dart';
import '../widgets/artwork.dart';
import '../widgets/pour_toi_actions.dart';

/// « Tes artistes », à la manière des bulles de Spotify : un toucher pour
/// aimer, deux pour adorer, un troisième pour retirer. Aimer une bulle en
/// fait éclore d'autres à côté — ses artistes proches —, ce qui permet de
/// décrire un goût en partant de trois noms. La recherche trouve aussi des
/// artistes hors de la bibliothèque : ils comptent quand même (leurs voisins
/// dans la bibliothèque en profitent, et « À découvrir ailleurs » part d'eux).
class ArtistesBullesScreen extends ConsumerStatefulWidget {
  const ArtistesBullesScreen({super.key});

  @override
  ConsumerState<ArtistesBullesScreen> createState() =>
      _ArtistesBullesScreenState();
}

class _ArtistesBullesScreenState extends ConsumerState<ArtistesBullesScreen> {
  List<Bulle>? _bulles;
  List<Bulle>? _resultats;
  Object? _erreur;
  bool _change = false;
  bool _cherche = false;
  Timer? _attente;
  final _champ = TextEditingController();

  /// Les bulles qui viennent d'éclore, pour les faire apparaître en douceur.
  final _neuves = <String>{};

  PourToiRepository get _repo => ref.read(pourToiRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _attente?.cancel();
    _champ.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final b = await _repo.bulles();
      // Une copie : la liste change sous nos doigts (bulles qui éclosent).
      if (mounted) setState(() => _bulles = [...b]);
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  void _surSaisie(String texte) {
    _attente?.cancel();
    if (texte.trim().length < 2) {
      setState(() {
        _resultats = null;
        _cherche = false;
      });
      return;
    }
    setState(() => _cherche = true);
    _attente = Timer(const Duration(milliseconds: 400), () async {
      try {
        final r = await _repo.chercherArtiste(texte.trim());
        if (mounted && _champ.text.trim() == texte.trim()) {
          // Ce qui est déjà choisi garde son niveau dans les résultats.
          final niveaux = {
            for (final b in _bulles ?? <Bulle>[]) b.cle: b.niveau,
          };
          setState(() {
            _resultats = [
              for (final b in r) b.avecNiveau(niveaux[b.cle] ?? b.niveau),
            ];
            _cherche = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _cherche = false);
      }
    });
  }

  /// Le niveau d'une bulle change : partout où elle est montrée, tout de
  /// suite ; le serveur suit. En cas d'échec, on revient en arrière.
  Future<void> _poser(Bulle b, int niveau) async {
    final avant = b.niveau;
    setState(() => _remplacer(b.cle, niveau, ajouter: b));
    _change = true;
    if (niveau == 1) {
      HapticFeedback.selectionClick();
    } else if (niveau == 2) {
      HapticFeedback.mediumImpact();
    }
    try {
      await _repo.choisir(b, niveau);
    } catch (e) {
      if (!mounted) return;
      setState(() => _remplacer(b.cle, avant));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Échec : $e')));
      return;
    }
    // Aimée pour la première fois : ses proches éclosent à côté.
    if (avant == 0 && niveau == 1) unawaited(_eclore(b));
  }

  void _remplacer(String cle, int niveau, {Bulle? ajouter}) {
    final liste = _bulles ??= [];
    final i = liste.indexWhere((x) => x.cle == cle);
    if (i >= 0) {
      liste[i] = liste[i].avecNiveau(niveau);
    } else if (ajouter != null && niveau > 0) {
      // Trouvée par la recherche : elle rejoint les bulles, en tête.
      liste.insert(0, ajouter.avecNiveau(niveau));
    }
    final r = _resultats;
    if (r != null) {
      final j = r.indexWhere((x) => x.cle == cle);
      if (j >= 0) r[j] = r[j].avecNiveau(niveau);
    }
  }

  Future<void> _eclore(Bulle b) async {
    try {
      final deja = (_bulles ?? const <Bulle>[]).map((x) => x.cle);
      final nouvelles = await _repo.autour(b, deja);
      if (!mounted || nouvelles.isEmpty) return;
      setState(() {
        final liste = _bulles!;
        final presentes = liste.map((x) => x.cle).toSet();
        final ajout = [
          for (final n in nouvelles)
            if (!presentes.contains(n.cle)) n,
        ];
        final i = liste.indexWhere((x) => x.cle == b.cle);
        liste.insertAll(i < 0 ? liste.length : i + 1, ajout);
        _neuves.addAll(ajout.map((x) => x.cle));
      });
    } catch (_) {
      // Rien n'éclot : la bulle reste aimée, c'est l'essentiel.
    }
  }

  Future<void> _menu(Bulle b) async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Artwork(
                url: b.image,
                size: 44,
                borderRadius: 22,
                icon: Icons.person,
              ),
              title: Text(b.nom),
              subtitle: Text(
                b.dansBibliotheque
                    ? 'Dans ta bibliothèque'
                    : 'Pas encore dans ta bibliothèque',
              ),
            ),
            const Divider(height: 1),
            for (final (n, libelle, icone) in const [
              (1, "J'aime", Icons.favorite_border),
              (2, "J'adore", Icons.favorite),
            ])
              if (b.niveau != n)
                ListTile(
                  leading: Icon(icone),
                  title: Text(libelle),
                  onTap: () {
                    Navigator.pop(ctx);
                    _poser(b, n);
                  },
                ),
            if (b.niveau > 0)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Retirer de mes artistes'),
                onTap: () {
                  Navigator.pop(ctx);
                  _poser(b, 0);
                },
              ),
            if (b.artistId != null) ...[
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text("Ouvrir l'artiste"),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/artist/${b.artistId}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.thumb_down_alt_outlined),
                title: const Text('Pas pour moi'),
                subtitle: const Text('Ne plus le proposer nulle part'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (b.niveau > 0) _poser(b, 0);
                  setState(() => _bulles?.removeWhere((x) => x.cle == b.cle));
                  rejectFromRecos(
                    messenger,
                    ref,
                    type: 'artist',
                    id: b.artistId!,
                    label: b.nom,
                  );
                },
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Le chercher pour l\'écouter'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(searchQueryProvider.notifier).set(b.nom);
                  context.go('/search');
                },
              ),
          ],
        ),
      ),
    );
  }

  /// En partant : profil et mix recalculés tout de suite, pour que l'accueil
  /// reflète déjà les choix.
  Future<void> _terminer() async {
    if (_change) {
      try {
        await _repo.analyser();
      } catch (_) {
        // La nuit s'en chargera.
      }
      ref.invalidate(goutsProfilProvider);
      ref.invalidate(pourToiAccueilProvider);
    }
    if (!mounted) return;
    // Plus rien à retenir : on laisse le retour se faire, au prochain dessin
    // (PopScope relit `canPop` à la reconstruction).
    setState(() => _change = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Ouvert directement (sans écran derrière) : on rejoint « Tes goûts ».
      context.canPop() ? context.pop() : context.go('/gouts');
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final choisies = (_bulles ?? const <Bulle>[])
        .where((b) => b.niveau > 0)
        .length;
    final montrees = _resultats ?? _bulles;

    return PopScope(
      canPop: !_change,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _terminer();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tes artistes'),
          actions: [
            TextButton(onPressed: _terminer, child: const Text('Terminé')),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _champ,
                onChanged: _surSaisie,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Chercher un artiste',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _champ.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _champ.clear();
                            _surSaisie('');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                _resultats != null
                    ? 'Touche un artiste pour l\'ajouter.'
                    : 'Touche une fois pour aimer, deux pour adorer, '
                          'trois pour retirer. Garde le doigt pour plus. La '
                          'recherche trouve aussi ceux que tu n\'as pas.'
                          '${choisies > 0 ? '  ·  $choisies choisis' : ''}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_cherche) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _erreur != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Ton serveur ne connaît pas encore « Tes artistes » : '
                          'mets-le à jour.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : montrees == null
                  ? const Center(child: CircularProgressIndicator())
                  : montrees.isEmpty
                  ? Center(
                      child: Text(
                        'Aucun artiste trouvé.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        MediaQuery.paddingOf(context).bottom + 24,
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 14,
                        children: [
                          for (final b in montrees)
                            BulleArtiste(
                              key: ValueKey(b.cle),
                              bulle: b,
                              neuve: _neuves.contains(b.cle),
                              onTap: () => _poser(
                                b,
                                _resultats != null && b.niveau == 0
                                    ? 1
                                    : (b.niveau + 1) % 3,
                              ),
                              onLongPress: () => _menu(b),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une bulle : la photo en rond, qui grossit quand on l'aime et plus encore
/// quand on l'adore, avec un cœur (un ou deux) pour le dire sans couleur.
class BulleArtiste extends StatelessWidget {
  const BulleArtiste({
    super.key,
    required this.bulle,
    required this.onTap,
    this.onLongPress,
    this.neuve = false,
  });

  final Bulle bulle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Vient d'éclore : elle apparaît en grandissant.
  final bool neuve;

  static double tailleDe(int niveau) => switch (niveau) {
    2 => 104,
    1 => 92,
    _ => 80,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = bulle;
    final taille = tailleDe(b.niveau);
    final etat = switch (b.niveau) {
      2 => 'adoré',
      1 => 'aimé',
      _ => 'pas choisi',
    };
    Widget bulleWidget = SizedBox(
      width: 112,
      child: Semantics(
        button: true,
        label: '${b.nom}, $etat',
        hint: 'Touche pour changer, garde le doigt pour plus de choix',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 108,
                  height: 108,
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          width: taille,
                          height: taille,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: b.niveau > 0
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: b.niveau == 2
                                  ? 4
                                  : (b.niveau == 1 ? 3 : 1),
                            ),
                          ),
                          padding: const EdgeInsets.all(3),
                          child: ClipOval(
                            child: Artwork(
                              url: b.image,
                              size: taille,
                              borderRadius: taille / 2,
                              icon: Icons.person,
                            ),
                          ),
                        ),
                        if (b.niveau > 0)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: scheme.surface,
                                  width: 2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 3,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (var i = 0; i < b.niveau; i++)
                                      Icon(
                                        Icons.favorite,
                                        size: 14,
                                        color: scheme.onPrimary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  b.nom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.15,
                    fontWeight: b.niveau > 0
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
                if (!b.dansBibliotheque)
                  Text(
                    'pas dans ta biblio',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (neuve) {
      bulleWidget = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.4, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Opacity(
          opacity: v.clamp(0, 1),
          child: Transform.scale(scale: v, child: child),
        ),
        child: bulleWidget,
      );
    }
    return bulleWidget;
  }
}

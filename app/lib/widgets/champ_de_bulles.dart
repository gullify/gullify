import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../api/pour_toi_repository.dart';
import 'artwork.dart';

/// Le champ de bulles de « Tes artistes » : un graphe d'artistes reliés
/// qu'on déplie, à la manière de la vue « graphe » d'Obsidian ou des
/// explorateurs d'artistes proches (Music-Map, Related Artists Explorer).
///
///  - Un arbre, pas une toile : chaque bulle a UN parent — celle d'où elle a
///    éclos, ou l'artiste choisi qui l'a fait pousser — et ne le quitte
///    plus. Aimer un satellite ne le détache pas : il grossit sur place et
///    ses propres proches poussent autour de lui (et ainsi de suite).
///    Deux artistes choisis proches l'un de l'autre se retrouvent sur la
///    même branche. Un seul trait par bulle, vers son parent : lisible, pas
///    de spaghetti (demande de Maxime, après le réseau de la 3.88.0).
///  - Taille : un artiste choisi est gros, d'autant plus qu'il a de
///    branches ; un proche non choisi est petit, plus petit en profondeur.
///  - Placement : chaque arbre pousse — la racine déplie ses enfants tout
///    autour d'elle, chaque autre bulle déplie les siens en éventail vers
///    l'extérieur, dans le prolongement de sa branche ; les arbres et les
///    bulles seules (écoutées, d'ailleurs) se rangent en étagères. Chaque
///    bulle est rappelée vers sa place par un ressort amorti, et les bulles
///    qui se touchent s'écartent doucement.
///  - Toujours vivant, quel que soit le réglage d'animations du téléphone
///    (demande de Maxime) : elles flottent, rebondissent quand on aime,
///    des cœurs jaillissent (adorer : une onde en plus) et les bulles qui
///    éclosent sortent de leur parent.
///
/// Le champ calcule sa propre hauteur : le placer dans un défilement.
class ChampDeBulles extends StatefulWidget {
  const ChampDeBulles({
    super.key,
    required this.bulles,
    required this.onTap,
    this.onLongPress,
    this.origines = const {},
  });

  final List<Bulle> bulles;
  final void Function(Bulle) onTap;
  final void Function(Bulle)? onLongPress;

  /// Bulles qui viennent d'éclore → clé de la bulle d'où elles sortent.
  final Map<String, String> origines;

  @override
  State<ChampDeBulles> createState() => _ChampDeBullesState();
}

class _Corps {
  _Corps(this.cle, this.x, this.y, this.r, this.phase);

  final String cle;
  double x, y, vx = 0, vy = 0;
  double r, vr = 0;
  double ax = 0, ay = 0; // la place visée (racines et bulles seules)
  double cible = 30; // le rayon visé
  final double phase; // pour flotter chacune à son rythme
  double apparition = 0; // délai avant d'éclore (secondes)
}

class _Particule {
  _Particule(
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.taille, {
    this.onde = false,
    this.r0 = 0,
  });

  double x, y, vx, vy;
  final double taille;
  final bool onde;
  final double r0;
  double age = 0;
  static const vie = 0.9;
}

class _ChampDeBullesState extends State<ChampDeBulles>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _corps = <String, _Corps>{};
  final _particules = <_Particule>[];
  final _hasard = Random();
  final _niveaux = <String, int>{};
  Duration _dernier = Duration.zero;
  double _t = 0;
  double _largeur = 0;
  double _hauteur = 200;

  /// Bulle → son parent dans l'arbre. Gardé d'une image à l'autre : une
  /// bulle ne change jamais de parent tant qu'il est là.
  final _parent = <String, String>{};

  var _enfants = <String, List<String>>{};
  var _racines = <String>[]; // choisies (ou dépliées) sans parent
  var _seules = <String>[]; // ni parent ni enfant
  var _rayons = <String, double>{};

  /// Plus petit que ça : une « petite » bulle (nom sur une ligne, en gris).
  static const petite = 26.0;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChampDeBulles old) {
    super.didUpdateWidget(old);
    // Un niveau a changé : une fête (ou un dégonflement), et on réveille.
    for (final b in widget.bulles) {
      final avant = _niveaux[b.cle];
      if (avant != null && avant != b.niveau) _celebrer(b.cle, avant, b.niveau);
    }
    _reveiller();
  }

  void _reveiller() {
    if (!_ticker.isActive) {
      _dernier = Duration.zero;
      _ticker.start();
    }
  }

  /// [v] est-il [u] ou l'un de ses ancêtres ?
  bool _ancetre(String v, String u) {
    String? x = u;
    for (var i = 0; x != null && i < 500; i++) {
      if (x == v) return true;
      x = _parent[x];
    }
    return false;
  }

  /// L'arbre : qui pousse de qui, et la taille de chacun.
  void _organiser() {
    final bulles = widget.bulles;
    final presentes = {for (final b in bulles) b.cle};
    final rang = {for (final (i, b) in bulles.indexed) b.cle: i};
    final voisins = <String, Set<String>>{};
    void relier(String a, String b) {
      if (a == b || !presentes.contains(a) || !presentes.contains(b)) return;
      voisins.putIfAbsent(a, () => {}).add(b);
      voisins.putIfAbsent(b, () => {}).add(a);
    }

    for (final b in bulles) {
      for (final l in b.liens) {
        relier(b.cle, l);
      }
    }
    widget.origines.forEach((enfant, mere) => relier(mere, enfant));

    // Un parent parti : la bulle redevient libre (et sera reprise).
    _parent.removeWhere(
      (e, p) => !presentes.contains(e) || !presentes.contains(p),
    );
    // Celles qui ont éclos : de leur bulle mère, toujours.
    widget.origines.forEach((enfant, mere) {
      if (presentes.contains(enfant) &&
          presentes.contains(mere) &&
          !_parent.containsKey(enfant) &&
          !_ancetre(enfant, mere)) {
        _parent[enfant] = mere;
      }
    });
    // Les autres : un artiste choisi (ou déjà déplié) prend sous lui ses
    // proches encore libres, dans l'ordre de la liste — les choisis d'abord.
    final niveaux = {for (final b in bulles) b.cle: b.niveau};
    final porteurs = {..._parent.values};
    for (final b in bulles) {
      if (b.niveau == 0 && !porteurs.contains(b.cle)) continue;
      final proches = [...?voisins[b.cle]]
        ..sort((a, c) => rang[a]!.compareTo(rang[c]!));
      for (final v in proches) {
        if (_parent.containsKey(v) || _ancetre(v, b.cle)) continue;
        _parent[v] = b.cle;
        porteurs.add(b.cle);
      }
    }

    final enfants = <String, List<String>>{};
    for (final b in bulles) {
      final p = _parent[b.cle];
      if (p != null) enfants.putIfAbsent(p, () => []).add(b.cle);
    }
    final racines = <String>[];
    final seules = <String>[];
    for (final b in bulles) {
      if (_parent.containsKey(b.cle)) continue;
      if (b.niveau > 0 || enfants.containsKey(b.cle)) {
        racines.add(b.cle);
      } else {
        seules.add(b.cle);
      }
    }

    final rayons = <String, double>{};
    for (final b in bulles) {
      final n = enfants[b.cle]?.length ?? 0;
      final profond = _parent.containsKey(_parent[b.cle]);
      rayons[b.cle] = switch (niveaux[b.cle]) {
        2 => 46 + min(n, 6) * 2.5,
        1 => 38 + min(n, 6) * 2.5,
        _ when n > 0 => 28 + min(n, 6) * 2.0,
        _ when _parent.containsKey(b.cle) => profond ? 18 : 21,
        _ => 30,
      };
    }
    _enfants = enfants;
    _racines = racines;
    _seules = seules;
    _rayons = rayons;
  }

  /// La boîte d'une bulle autour de son centre : demi-largeur, ce qui
  /// dépasse au-dessus, ce qui dépasse dessous (le nom).
  (double, double, double) _boiteDe(double r) =>
      r < petite ? (max(r, 38), r, r + 16) : (max(r, 52), r, r + 34);

  /// Un arbre qui pousse : la racine déplie ses enfants tout autour
  /// d'elle ; chaque autre bulle déplie les siens en éventail, vers
  /// l'extérieur, dans le prolongement de sa branche. Les branches touffues
  /// prennent plus d'angle. Remplit [rel] (places par rapport à la racine)
  /// et rend la boîte de l'arbre, noms compris.
  Rect _deployer(String racine, Map<String, Offset> rel, double largeur) {
    double r(String u) => _rayons[u] ?? 20;
    final feuilles = <String, int>{};
    int compter(String u) {
      final e = _enfants[u] ?? const <String>[];
      return feuilles[u] = e.isEmpty ? 1 : e.fold(0, (s, x) => s + compter(x));
    }

    compter(racine);
    var profondeur = 0;
    void deployer(String u, Offset pos, double? cap, int k) {
      final e = _enfants[u] ?? const <String>[];
      if (e.isEmpty || k > 12) return;
      profondeur = max(profondeur, k + 1);
      final poids = [for (final x in e) 1.0 + (feuilles[x]! - 1) * 0.6];
      final total = poids.fold(0.0, (s, p) => s + p);
      final ouverture = cap == null ? 2 * pi : min(1.6 * pi, 0.85 * total);
      var a = cap == null
          ? -pi / 2 + 0.35 + (u.hashCode % 40) / 100
          : cap - ouverture / 2;
      for (final (i, x) in e.indexed) {
        final part = ouverture * poids[i] / total;
        final angle = a + part / 2;
        // Assez loin pour la place des deux, du nom, et de l'arc.
        var d = r(u) + r(x) + 30 + ((_enfants[x]?.isNotEmpty ?? false) ? 22 : 0);
        d = max(d, 84 / max(part, 0.3));
        if (cap == null && e.length == 1) d += 10;
        final p = pos + Offset(cos(angle), sin(angle)) * d;
        rel[x] = p;
        deployer(x, p, angle, k + 1);
        a += part;
      }
    }

    rel[racine] = Offset.zero;
    deployer(racine, Offset.zero, null, 0);

    Rect boite() {
      var b = Rect.zero;
      for (final MapEntry(key: u, value: o) in rel.entries) {
        final (g, h, bas) = _boiteDe(r(u));
        b = b.expandToInclude(Rect.fromLTRB(o.dx - g, o.dy - h, o.dx + g, o.dy + bas));
      }
      return b;
    }

    var b = boite();
    // Trop large pour l'écran : on l'étire en hauteur (les distances
    // restent à peu près les mêmes, les bulles ne se tassent pas).
    if (b.width > largeur - 8) {
      final f = (largeur - 8) / b.width;
      rel.updateAll((_, o) => Offset(o.dx * f, o.dy / f));
      b = boite();
    }
    return b;
  }

  /// Les places : chaque arbre (et chaque bulle seule) rangé en étagères
  /// d'après sa boîte, l'espace qui reste réparti entre eux.
  void _placer(double largeur) {
    final arbres = <String, Map<String, Offset>>{};
    final elements = <(String, Rect)>[];
    for (final racine in [..._racines, ..._seules]) {
      final rel = <String, Offset>{};
      final r = _rayons[racine] ?? 30;
      if (_enfants.containsKey(racine)) {
        elements.add((racine, _deployer(racine, rel, largeur)));
      } else {
        rel[racine] = Offset.zero;
        final biblio = widget.bulles
            .firstWhere((b) => b.cle == racine)
            .dansBibliotheque;
        final (g, h, bas) = _boiteDe(r);
        elements.add((racine, Rect.fromLTRB(-g, -h, g, bas + (biblio ? 0 : 14))));
      }
      arbres[racine] = rel;
    }

    var haut = 8.0;
    var i = 0;
    while (i < elements.length) {
      // Une étagère : autant d'éléments que la largeur en tient.
      final rangee = [elements[i++]];
      var pris = rangee.first.$2.width + 8;
      while (i < elements.length && pris + elements[i].$2.width + 8 <= largeur) {
        pris += elements[i].$2.width + 8;
        rangee.add(elements[i++]);
      }
      final dessus = rangee.map((e) => -e.$2.top).reduce(max);
      final dessous = rangee.map((e) => e.$2.bottom).reduce(max);
      final jeu = (largeur - pris) / (rangee.length + 1) + 8;
      var x = jeu - 4;
      for (final (cle, b) in rangee) {
        final cx = x - b.left;
        final cy = haut + dessus;
        for (final MapEntry(key: u, value: o) in arbres[cle]!.entries) {
          final c = _corps[u];
          if (c == null) continue;
          c.ax = cx + o.dx;
          c.ay = cy + o.dy;
        }
        x += b.width + jeu;
      }
      haut += dessus + dessous + 10;
    }
    _hauteur = haut + 16;
  }

  /// Les corps suivent la liste : ceux qui arrivent naissent (au premier
  /// affichage, les racines à leur place et les branches sortant de leur
  /// parent, chacune son tour ; dans la bulle mère si elles éclosent),
  /// ceux qui partent disparaissent.
  void _synchroniser(double largeur) {
    final premierAffichage = _corps.isEmpty;
    final presentes = <String>{};
    for (final (i, b) in widget.bulles.indexed) {
      presentes.add(b.cle);
      _niveaux.putIfAbsent(b.cle, () => b.niveau);
      if (_corps.containsKey(b.cle)) continue;
      final mere = _corps[widget.origines[b.cle]];
      final c = _Corps(
        b.cle,
        mere?.x ?? largeur / 2,
        mere?.y ?? 80,
        0,
        _hasard.nextDouble() * pi * 2,
      );
      if (mere != null) {
        // Éjectée de la bulle mère, dans une direction au hasard.
        final a = _hasard.nextDouble() * pi * 2;
        c.vx = cos(a) * 260;
        c.vy = sin(a) * 260;
      } else {
        c.apparition = premierAffichage ? i * 0.03 : 0;
      }
      _corps[b.cle] = c;
    }
    _corps.removeWhere((k, _) => !presentes.contains(k));
    _placer(largeur);
    if (premierAffichage) {
      for (final cle in [..._racines, ..._seules]) {
        final c = _corps[cle]!;
        c.x = c.ax;
        c.y = c.ay + 30;
      }
      // Les branches, génération par génération, sortent de leur parent.
      var generation = _racines;
      while (generation.isNotEmpty) {
        final suivante = <String>[];
        for (final p in generation) {
          final cp = _corps[p]!;
          for (final (j, e) in (_enfants[p] ?? const <String>[]).indexed) {
            final c = _corps[e]!;
            final a = _hasard.nextDouble() * pi * 2;
            c.x = cp.x + cos(a) * 4;
            c.y = cp.y + sin(a) * 4;
            c.vx = cos(a) * 180;
            c.vy = sin(a) * 180;
            c.apparition = cp.apparition + 0.2 + j * 0.03;
            suivante.add(e);
          }
        }
        generation = suivante;
      }
    }
  }

  void _celebrer(String cle, int avant, int apres) {
    _niveaux[cle] = apres;
    final c = _corps[cle];
    if (c == null) return;
    if (apres > avant) {
      c.vr += 420; // le petit « pop » au-delà de la taille visée
      final n = apres == 2 ? 10 : 6;
      for (var i = 0; i < n; i++) {
        final a = -pi / 2 + (_hasard.nextDouble() - 0.5) * pi * 1.3;
        final v = 140 + _hasard.nextDouble() * 160;
        _particules.add(
          _Particule(
            c.x,
            c.y - c.r * 0.3,
            cos(a) * v,
            sin(a) * v,
            12 + _hasard.nextDouble() * 8,
          ),
        );
      }
      if (apres == 2) {
        _particules.add(_Particule(c.x, c.y, 0, 0, 0, onde: true, r0: c.r));
      }
    } else {
      c.vr -= 200; // le dégonflement
    }
  }

  void _tick(Duration maintenant) {
    final dt = _dernier == Duration.zero
        ? 1 / 60
        : ((maintenant - _dernier).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _dernier = maintenant;
    _t += dt;

    final vivants = [
      for (final c in _corps.values)
        if (c.apparition <= 0) c,
    ];
    for (final c in _corps.values) {
      if (c.apparition > 0) {
        c.apparition -= dt;
        continue;
      }
      // Rayon : ressort amorti (le rebond).
      c.vr += ((c.cible - c.r) * 320 - c.vr * 16) * dt;
      c.r = max(0, c.r + c.vr * dt);
      // Place : ressort amorti.
      c.vx += ((c.ax - c.x) * 22 - c.vx * 7) * dt;
      c.vy += ((c.ay - c.y) * 22 - c.vy * 7) * dt;
      c.x += c.vx * dt;
      c.y += c.vy * dt;
    }
    // Les bulles se repoussent quand elles se touchent : une bulle qui
    // gonfle écarte ses voisines. Doucement, pour que chacune puisse
    // glisser entre les autres jusqu'à sa place.
    for (var i = 0; i < vivants.length; i++) {
      for (var j = i + 1; j < vivants.length; j++) {
        final a = vivants[i], b = vivants[j];
        final dx = b.x - a.x, dy = b.y - a.y;
        final d = sqrt(dx * dx + dy * dy);
        final mini = a.r + b.r + 8;
        if (d >= mini || d == 0) continue;
        final pousse = (mini - d) / d * 0.25;
        a.vx -= dx * pousse * 6;
        a.vy -= dy * pousse * 6;
        b.vx += dx * pousse * 6;
        b.vy += dy * pousse * 6;
      }
    }
    for (final c in vivants) {
      c.x = c.x.clamp(c.r + 2, max(c.r + 2, _largeur - c.r - 2));
      c.y = max(c.y, c.r + 4);
    }
    // Les cœurs montent, ralentissent et s'effacent.
    for (final p in _particules) {
      p.age += dt;
      p.vy += 260 * dt;
      p.vx *= 1 - 2 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
    _particules.removeWhere((p) => p.age >= _Particule.vie);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, contraintes) {
        final largeur = contraintes.maxWidth;
        _organiser();
        for (final c in _corps.values) {
          c.cible = _rayons[c.cle] ?? 30;
        }
        if (largeur != _largeur ||
            _corps.length != widget.bulles.length ||
            widget.bulles.any((b) => !_corps.containsKey(b.cle))) {
          _largeur = largeur;
          _synchroniser(largeur);
          for (final c in _corps.values) {
            c.cible = _rayons[c.cle] ?? 30;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reveiller();
          });
        } else {
          _placer(largeur);
        }
        // Un trait par bulle, vers son parent, bord à bord.
        final niveaux = {for (final b in widget.bulles) b.cle: b.niveau};
        final branches = <(Offset, Offset, double, bool)>[];
        _parent.forEach((e, p) {
          final s = _corps[e], a = _corps[p];
          if (s == null || a == null) return;
          final cs = _centre(s), ca = _centre(a);
          final ecart = ca - cs;
          if (ecart.distance <= s.r + a.r + 4) return;
          final sens = ecart / ecart.distance;
          branches.add((
            cs + sens * (s.r + 3),
            ca - sens * (a.r + 3),
            (min(s.r / s.cible, a.r / a.cible)).clamp(0.0, 1.0),
            (niveaux[p] ?? 0) > 0,
          ));
        });
        return SizedBox(
          width: largeur,
          height: _hauteur,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _Branches(branches, couleur: scheme.primary),
                  ),
                ),
              ),
              // Les petites par-dessus : elles resteraient sinon sous la
              // zone de toucher d'une grosse voisine (son nom compris).
              for (final petites in [false, true])
                for (final b in widget.bulles)
                  if (((_rayons[b.cle] ?? 30) < petite) == petites)
                    if (_corps[b.cle] case final c?)
                      _bulle(b, c, scheme, satellite: petites),
              for (final p in _particules) _particule(p, scheme),
            ],
          ),
        );
      },
    );
  }

  double _flotte(_Corps c) => sin(_t * 1.4 + c.phase) * 3.0;

  /// Le centre du rond, tel qu'il est dessiné (flottement compris).
  Offset _centre(_Corps c) => Offset(c.x, c.y + _flotte(c));

  Widget _bulle(
    Bulle b,
    _Corps c,
    ColorScheme scheme, {
    required bool satellite,
  }) {
    final flotte = _flotte(c);
    final r = c.r;
    final largeurEtiquette = satellite ? 84.0 : 112.0;
    final etat = switch (b.niveau) {
      2 => 'adoré',
      1 => 'aimé',
      _ => 'pas choisi',
    };
    final visible = r > 1;
    return Positioned(
      left: c.x - largeurEtiquette / 2,
      top: c.y - r + flotte,
      width: largeurEtiquette,
      child: IgnorePointer(
        ignoring: !visible,
        child: Opacity(
          opacity: (r / min(c.cible, 20)).clamp(0.0, 1.0),
          child: Semantics(
            button: true,
            label: '${b.nom}, $etat',
            hint: 'Touche pour changer, garde le doigt pour plus de choix',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _reveiller();
                widget.onTap(b);
              },
              onLongPress: widget.onLongPress == null
                  ? null
                  : () => widget.onLongPress!(b),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: max(1, r * 2),
                    height: max(1, r * 2),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
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
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (b.niveau > 0
                                              ? scheme.primary
                                              : scheme.shadow)
                                          .withValues(
                                            alpha: b.niveau > 0 ? 0.35 : 0.15,
                                          ),
                                  blurRadius: b.niveau > 0 ? 18 : 10,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(satellite ? 2 : 3),
                              child: ClipOval(
                                child: Artwork(
                                  url: b.image,
                                  // Décodée à la plus grande taille : pas de
                                  // nouveau décodage à chaque image du rebond.
                                  size: 136,
                                  borderRadius: 999,
                                  icon: Icons.person,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (b.niveau > 0)
                          Positioned(
                            right: -4,
                            bottom: -2,
                            child: _Badge(niveau: b.niveau, scheme: scheme),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: satellite ? 2 : 4),
                  Text(
                    b.nom,
                    maxLines: satellite ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: satellite ? 11 : 13,
                      height: 1.15,
                      fontWeight: b.niveau > 0
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: satellite ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (!b.dansBibliotheque && !satellite)
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
      ),
    );
  }

  Widget _particule(_Particule p, ColorScheme scheme) {
    final f = (p.age / _Particule.vie).clamp(0.0, 1.0);
    if (p.onde) {
      final r = p.r0 + 40 * Curves.easeOut.transform(f);
      return Positioned(
        left: p.x - r,
        top: p.y - r,
        child: IgnorePointer(
          child: Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.primary.withValues(alpha: (1 - f) * 0.8),
                width: 3,
              ),
            ),
          ),
        ),
      );
    }
    final taille = p.taille * (0.6 + 0.6 * sin(f * pi));
    return Positioned(
      left: p.x - taille / 2,
      top: p.y - taille / 2,
      child: IgnorePointer(
        child: Opacity(
          opacity: 1 - f,
          child: Icon(Icons.favorite, size: taille, color: scheme.primary),
        ),
      ),
    );
  }
}

/// Les branches : un trait court de chaque bulle vers son parent, derrière
/// les bulles — plus marqué quand le parent est un artiste choisi.
class _Branches extends CustomPainter {
  _Branches(this.branches, {required this.couleur});

  final List<(Offset, Offset, double, bool)> branches;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (de, vers, opacite, fort) in branches) {
      trait
        ..color = couleur.withValues(alpha: (fort ? 0.5 : 0.3) * opacite)
        ..strokeWidth = fort ? 2 : 1.3;
      canvas.drawLine(de, vers, trait);
    }
  }

  @override
  bool shouldRepaint(_Branches old) => true;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.niveau, required this.scheme});

  final int niveau;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: scheme.surface, width: 2),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < niveau; i++)
            Icon(Icons.favorite, size: 14, color: scheme.onPrimary),
        ],
      ),
    ),
  );
}

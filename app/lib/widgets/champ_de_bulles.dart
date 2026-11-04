import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../api/pour_toi_repository.dart';
import 'artwork.dart';

/// Le champ de bulles de « Tes artistes » : des bulles vivantes, à la manière
/// de l'accueil d'Apple Music et de Spotify, rangées en petits systèmes
/// solaires.
///
///  - chaque artiste choisi est un astre : une grosse bulle, d'autant plus
///    grosse qu'il a de connexions (Bulle.liens, et les bulles qui en ont
///    éclos) ;
///  - ses proches sont de petits satellites qui tournent lentement autour de
///    lui, reliés par un rayon court — un seul fil chacun, vers son astre :
///    pas de toile à démêler (demande de Maxime, après le « réseau
///    neuronal » de la 3.88.0, trop spaghetti) ;
///  - un satellite relié à plusieurs astres grossit un peu ; un satellite
///    qu'on aime devient à son tour un astre ;
///  - les bulles sans lien (écoutées, d'ailleurs) se rangent entre les
///    systèmes.
///
/// Une petite simulation physique, image par image : chaque bulle est
/// rappelée vers sa place par un ressort amorti, les bulles se repoussent
/// quand elles se touchent, le rayon suit lui aussi un ressort (le rebond
/// quand on aime), elles flottent toujours — quel que soit le réglage
/// d'animations du téléphone (demande de Maxime) —, aimer fait jaillir des
/// cœurs (adorer, une onde en plus) et les bulles qui éclosent sortent de
/// celle qu'on vient d'aimer.
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
  double ax = 0, ay = 0; // la place visée
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

  /// Satellite → son astre.
  var _astreDe = <String, String>{};

  /// Astre → ses satellites, dans l'ordre de la liste.
  var _satellites = <String, List<String>>{};

  /// Le rayon visé de chaque bulle.
  var _rayons = <String, double>{};

  static const _etiquette = 18.0; // la place du nom sous une bulle
  static const _rayonSatellite = 22.0;
  static const _sousLeNom = 40.0; // le nom d'un astre, sous lui
  static const _nom = 44.0; // le nom d'une bulle seule (deux lignes)

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

  /// Qui est astre, qui tourne autour de qui, et la taille de chacun.
  void _organiser() {
    final presentes = {for (final b in widget.bulles) b.cle};
    final voisins = <String, Set<String>>{};
    void relier(String a, String b) {
      if (a == b || !presentes.contains(a) || !presentes.contains(b)) return;
      voisins.putIfAbsent(a, () => {}).add(b);
      voisins.putIfAbsent(b, () => {}).add(a);
    }

    for (final b in widget.bulles) {
      for (final l in b.liens) {
        relier(b.cle, l);
      }
    }
    widget.origines.forEach((enfant, mere) => relier(mere, enfant));

    final astres = {
      for (final b in widget.bulles)
        if (b.niveau > 0) b.cle,
    };
    final rang = {for (final (i, b) in widget.bulles.indexed) b.cle: i};
    final astreDe = <String, String>{};
    final satellites = <String, List<String>>{};
    for (final b in widget.bulles) {
      if (astres.contains(b.cle)) continue;
      // Sa bulle mère d'abord ; sinon le premier astre de la liste qui lui
      // est proche.
      final mere = widget.origines[b.cle];
      String? astre = mere != null && astres.contains(mere) ? mere : null;
      if (astre == null) {
        final candidats = [
          for (final v in voisins[b.cle] ?? const <String>{})
            if (astres.contains(v)) v,
        ]..sort((a, c) => rang[a]!.compareTo(rang[c]!));
        if (candidats.isNotEmpty) astre = candidats.first;
      }
      if (astre == null) continue;
      astreDe[b.cle] = astre;
      satellites.putIfAbsent(astre, () => []).add(b.cle);
    }

    final rayons = <String, double>{};
    for (final b in widget.bulles) {
      final degre = (voisins[b.cle] ?? const <String>{}).length;
      rayons[b.cle] = astres.contains(b.cle)
          ? (b.niveau >= 2 ? 50.0 : 42.0) + min(degre, 6) * 2.5
          : astreDe.containsKey(b.cle)
          ? _rayonSatellite + min(max(degre - 1, 0), 3) * 3.0
          : 32.0;
    }
    _astreDe = astreDe;
    _satellites = satellites;
    _rayons = rayons;
  }

  /// Les orbites d'un astre : combien de satellites sur chacune, et à quelle
  /// distance du centre.
  List<(int, double)> _orbites(double rayonAstre, int n) {
    final out = <(int, double)>[];
    var rho = rayonAstre + _rayonSatellite + 22;
    var reste = n;
    while (reste > 0) {
      final place = max(3, (2 * pi * rho / (_rayonSatellite * 2 + 16)).floor());
      final ici = min(place, reste);
      out.add((ici, rho));
      reste -= ici;
      rho += _rayonSatellite * 2 + 26;
    }
    return out;
  }

  /// La place de chaque bulle : les systèmes (et les bulles seules) rangés
  /// en étagères, l'espace qui reste réparti entre eux ; les satellites sur
  /// leurs orbites, qui tournent lentement.
  void _placer(double largeur) {
    // Ce qui occupe une place dans les étagères : astres et bulles seules,
    // avec leur demi-largeur, ce qui dépasse au-dessus du centre et ce qui
    // dépasse en dessous (le nom, et l'orbite étirée vers le bas).
    final elements = <(String, double, double, double)>[];
    for (final b in widget.bulles) {
      if (_astreDe.containsKey(b.cle)) continue;
      final r = _rayons[b.cle] ?? 32;
      final sats = _satellites[b.cle] ?? const [];
      final orbites = _orbites(r, sats.length);
      if (orbites.isEmpty) {
        final nom = b.dansBibliotheque ? _nom : _nom + 14;
        elements.add((b.cle, max(r, 56) + 2, r + 4, r + nom));
      } else {
        final rho = orbites.last.$2;
        elements.add((
          b.cle,
          min(rho + 42, largeur / 2),
          rho + _rayonSatellite + 4,
          rho + _sousLeNom + _rayonSatellite + _etiquette,
        ));
      }
    }

    var haut = 8.0;
    var i = 0;
    while (i < elements.length) {
      // Une étagère : autant d'éléments que la largeur en tient.
      final rangee = [elements[i++]];
      var pris = rangee.first.$2 * 2;
      while (i < elements.length && pris + elements[i].$2 * 2 <= largeur) {
        pris += elements[i].$2 * 2;
        rangee.add(elements[i++]);
      }
      final dessus = rangee.map((e) => e.$3).reduce(max);
      final dessous = rangee.map((e) => e.$4).reduce(max);
      final jeu = (largeur - pris) / (rangee.length + 1);
      var x = jeu;
      for (final (cle, demi, _, _) in rangee) {
        final c = _corps[cle]!;
        final h = cle.hashCode;
        c.ax = x + demi + ((h % 13) - 6);
        c.ay = haut + dessus + (((h >> 5) % 9) - 4);
        x += demi * 2 + jeu;
      }
      haut += dessus + dessous;
    }
    _hauteur = haut + 16;

    // Les satellites : sur leurs orbites, autour de la place de leur astre.
    for (final MapEntry(key: astre, value: sats) in _satellites.entries) {
      final centre = _corps[astre];
      if (centre == null) continue;
      final depart = (astre.hashCode % 628) / 100;
      var k = 0;
      for (final (j, (n, rho)) in _orbites(
        _rayons[astre] ?? 42,
        sats.length,
      ).indexed) {
        // Une orbite sur deux tourne dans l'autre sens.
        final tour = depart + _t * (j.isEven ? 0.12 : -0.09) + j * 0.4;
        for (var s = 0; s < n; s++) {
          final c = _corps[sats[k++]];
          if (c == null) continue;
          final a = tour + 2 * pi * s / n;
          // Une orbite un peu plus basse et plus haute que large : en
          // passant dessous, le satellite laisse la place au nom de l'astre.
          c.ax = centre.ax + cos(a) * rho;
          c.ay = centre.ay + _sousLeNom / 2 + sin(a) * (rho + _sousLeNom / 2);
        }
      }
    }
  }

  /// Les corps suivent la liste : ceux qui arrivent naissent (à leur place
  /// au premier affichage, chacun son tour, les satellites sortant de leur
  /// astre ; dans la bulle mère s'ils éclosent), ceux qui partent
  /// disparaissent.
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
        c.apparition = premierAffichage ? i * 0.035 : 0;
      }
      _corps[b.cle] = c;
    }
    _corps.removeWhere((k, _) => !presentes.contains(k));
    _placer(largeur);
    if (premierAffichage) {
      for (final c in _corps.values) {
        final astre = _corps[_astreDe[c.cle]];
        if (astre != null) {
          // Le satellite sort de son astre, un peu après lui.
          c.x = astre.ax;
          c.y = astre.ay;
          c.apparition = astre.apparition + 0.25;
        } else {
          c.x = c.ax;
          c.y = c.ay + 30;
        }
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

    final corps = _corps.values.toList();
    for (final c in corps) {
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
    // Les bulles se repoussent quand elles se touchent.
    for (var i = 0; i < corps.length; i++) {
      for (var j = i + 1; j < corps.length; j++) {
        final a = corps[i], b = corps[j];
        final dx = b.x - a.x, dy = b.y - a.y;
        final d = sqrt(dx * dx + dy * dy);
        final mini = a.r + b.r + 8;
        if (d >= mini || d == 0) continue;
        final pousse = (mini - d) / d * 0.5;
        a.x -= dx * pousse;
        a.y -= dy * pousse;
        b.x += dx * pousse;
        b.y += dy * pousse;
        a.vx -= dx * pousse * 6;
        a.vy -= dy * pousse * 6;
        b.vx += dx * pousse * 6;
        b.vy += dy * pousse * 6;
      }
    }
    for (final c in corps) {
      c.x = c.x.clamp(c.r + 2, max(c.r + 2, _largeur - c.r - 2));
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
        if (largeur != _largeur ||
            _corps.length != widget.bulles.length ||
            widget.bulles.any((b) => !_corps.containsKey(b.cle))) {
          _largeur = largeur;
          _synchroniser(largeur);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reveiller();
          });
        } else {
          _placer(largeur);
        }
        for (final c in _corps.values) {
          c.cible = _rayons[c.cle] ?? 32;
        }
        // Un rayon court de chaque satellite vers son astre, bord à bord.
        final rayons = <(Offset, Offset, double)>[];
        for (final MapEntry(key: sat, value: astre) in _astreDe.entries) {
          final s = _corps[sat], a = _corps[astre];
          if (s == null || a == null) continue;
          final cs = _centre(s), ca = _centre(a);
          final ecart = ca - cs;
          if (ecart.distance <= s.r + a.r + 4) continue;
          final sens = ecart / ecart.distance;
          rayons.add((
            cs + sens * (s.r + 3),
            ca - sens * (a.r + 3),
            (min(s.r / s.cible, a.r / a.cible)).clamp(0.0, 1.0),
          ));
        }
        return SizedBox(
          width: largeur,
          height: _hauteur,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _Rayons(rayons, couleur: scheme.primary),
                  ),
                ),
              ),
              // Les satellites par-dessus : petits, ils resteraient sinon
              // sous la zone de toucher de leur astre (son nom compris).
              for (final satellite in [false, true])
                for (final b in widget.bulles)
                  if (_astreDe.containsKey(b.cle) == satellite)
                    if (_corps[b.cle] case final c?)
                      _bulle(b, c, scheme, satellite: satellite),
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

/// Les rayons des satellites vers leur astre : des traits courts et fins,
/// derrière les bulles.
class _Rayons extends CustomPainter {
  _Rayons(this.rayons, {required this.couleur});

  final List<(Offset, Offset, double)> rayons;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;
    for (final (de, vers, opacite) in rayons) {
      trait.color = couleur.withValues(alpha: 0.4 * opacite);
      canvas.drawLine(de, vers, trait);
    }
  }

  @override
  bool shouldRepaint(_Rayons old) => true;
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

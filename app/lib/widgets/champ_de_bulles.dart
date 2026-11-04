import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../api/pour_toi_repository.dart';
import 'artwork.dart';

/// Le champ de bulles de « Tes artistes » : des bulles vivantes, à la manière
/// de l'accueil d'Apple Music et de Spotify.
///
/// Une petite simulation physique, image par image :
///  - chaque bulle est rappelée vers sa place (un nid d'abeilles un peu
///    désordonné) par un ressort amorti ;
///  - les bulles se repoussent quand elles se touchent : une bulle qui gonfle
///    écarte ses voisines ;
///  - le rayon suit lui aussi un ressort, d'où le rebond quand on aime ;
///  - au repos, elles flottent doucement, toujours — quel que soit le
///    réglage d'animations du téléphone (demande de Maxime) ;
///  - aimer fait jaillir des cœurs, adorer en plus une onde ;
///  - les bulles qui éclosent sortent de celle qu'on vient d'aimer ;
///  - un réseau, comme des neurones : un fil relie chaque bulle à ses
///    proches (Bulle.liens, et la bulle d'où elle a éclos), un léger ressort
///    les rapproche, et un influx court le long des fils qui partent d'un
///    artiste choisi.
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

  /// Rayon d'une bulle selon ce qu'on en pense.
  static double rayonDe(int niveau) => switch (niveau) {
    2 => 54,
    1 => 46,
    _ => 38,
  };

  @override
  State<ChampDeBulles> createState() => _ChampDeBullesState();
}

class _Corps {
  _Corps(this.cle, this.x, this.y, this.r, this.phase);

  final String cle;
  double x, y, vx = 0, vy = 0;
  double r, vr = 0;
  double ax = 0, ay = 0; // la place visée
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
  List<(String, String)> _fils = const [];

  static const _rangee = 150.0;
  static const _haut = 72.0;

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

  /// La place de chaque bulle : un nid d'abeilles, légèrement désordonné
  /// (le désordre dépend du nom : il ne change pas d'une image à l'autre).
  void _placer(double largeur) {
    final colonnes = max(2, (largeur / 120).floor());
    final cellule = largeur / colonnes;
    for (final (i, b) in widget.bulles.indexed) {
      final rangee = i ~/ colonnes;
      final colonne = i % colonnes;
      final h = b.cle.hashCode;
      final decalage = rangee.isOdd ? cellule * 0.22 : -cellule * 0.22;
      final c = _corps[b.cle]!;
      c.ax = (cellule * (colonne + 0.5) + decalage + ((h % 17) - 8)).clamp(
        c.r + 4,
        largeur - c.r - 4,
      );
      c.ay = _haut + rangee * _rangee + (((h >> 5) % 21) - 10);
    }
    final rangees = (widget.bulles.length / colonnes).ceil();
    _hauteur = _haut + rangees * _rangee + 10;
  }

  /// Les corps suivent la liste : ceux qui arrivent naissent (à leur place
  /// au premier affichage, chacun son tour ; dans la bulle mère s'ils
  /// éclosent), ceux qui partent disparaissent.
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
        mere?.y ?? _haut,
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
        c.x = c.ax;
        c.y = c.ay + 30;
      }
    }
  }

  /// Les fils du réseau entre bulles présentes, chaque paire une fois.
  List<(String, String)> _relier() {
    final presentes = {for (final b in widget.bulles) b.cle};
    final vues = <String>{};
    final out = <(String, String)>[];
    void relier(String a, String b) {
      if (a == b || !presentes.contains(a) || !presentes.contains(b)) return;
      if (vues.add(a.compareTo(b) < 0 ? '$a\u0000$b' : '$b\u0000$a')) {
        out.add((a, b));
      }
    }

    for (final b in widget.bulles) {
      for (final l in b.liens) {
        relier(b.cle, l);
      }
    }
    widget.origines.forEach((enfant, mere) => relier(mere, enfant));
    return out;
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

    final niveaux = {for (final b in widget.bulles) b.cle: b.niveau};
    final corps = _corps.values.toList();
    for (final c in corps) {
      if (c.apparition > 0) {
        c.apparition -= dt;
        continue;
      }
      // Rayon : ressort amorti (le rebond).
      final cible = ChampDeBulles.rayonDe(niveaux[c.cle] ?? 0);
      c.vr += ((cible - c.r) * 320 - c.vr * 16) * dt;
      c.r = max(0, c.r + c.vr * dt);
      // Place : ressort amorti.
      c.vx += ((c.ax - c.x) * 22 - c.vx * 7) * dt;
      c.vy += ((c.ay - c.y) * 22 - c.vy * 7) * dt;
      c.x += c.vx * dt;
      c.y += c.vy * dt;
    }
    // Les fils tirent un peu les proches l'un vers l'autre.
    for (final (ka, kb) in _fils) {
      final a = _corps[ka], b = _corps[kb];
      if (a == null || b == null) continue;
      final dx = b.x - a.x, dy = b.y - a.y;
      final d = sqrt(dx * dx + dy * dy);
      if (d <= 160) continue;
      final f = (d - 160) / d * 1.6 * dt;
      a.vx += dx * f;
      a.vy += dy * f;
      b.vx -= dx * f;
      b.vy -= dy * f;
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
        _fils = _relier();
        final choisies = {
          for (final b in widget.bulles)
            if (b.niveau > 0) b.cle,
        };
        final visibles = <_Fil>[];
        for (final (ka, kb) in _fils) {
          final a = _corps[ka], b = _corps[kb];
          if (a == null || b == null) continue;
          final opacite = min(a.r, b.r) / ChampDeBulles.rayonDe(0);
          if (opacite <= 0.02) continue;
          // L'influx part de l'artiste choisi.
          final (de, vers) = choisies.contains(kb) && !choisies.contains(ka)
              ? (b, a)
              : (a, b);
          // Du bord d'un rond au bord de l'autre : rien ne passe sur les
          // photos (ni sur celles qui chargent encore).
          final ca = _centre(de), cb = _centre(vers);
          final ecart = cb - ca;
          if (ecart.distance <= de.r + vers.r + 4) continue;
          final sens = ecart / ecart.distance;
          visibles.add(
            _Fil(
              ca + sens * (de.r + 2),
              cb - sens * (vers.r + 2),
              actif: choisies.contains(ka) || choisies.contains(kb),
              phase: ((ka.hashCode ^ kb.hashCode) % 1000) / 1000,
              opacite: opacite.clamp(0.0, 1.0),
            ),
          );
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
                    painter: _Reseau(
                      visibles,
                      _t,
                      actif: scheme.primary,
                      calme: scheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              for (final b in widget.bulles)
                if (_corps[b.cle] case final c?) _bulle(b, c, scheme),
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

  Widget _bulle(Bulle b, _Corps c, ColorScheme scheme) {
    final flotte = _flotte(c);
    final r = c.r;
    const largeurEtiquette = 112.0;
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
          opacity: (r / ChampDeBulles.rayonDe(0)).clamp(0.0, 1.0),
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
                              padding: const EdgeInsets.all(3),
                              child: ClipOval(
                                child: Artwork(
                                  url: b.image,
                                  // Décodée à la plus grande taille : pas de
                                  // nouveau décodage à chaque image du rebond.
                                  size: ChampDeBulles.rayonDe(2) * 2,
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

class _Fil {
  const _Fil(
    this.de,
    this.vers, {
    required this.actif,
    required this.phase,
    required this.opacite,
  });

  final Offset de, vers;
  final bool actif; // touche un artiste choisi
  final double phase;
  final double opacite;
}

/// Les fils du réseau, derrière les bulles : des courbes douces, et sur
/// ceux qui partent d'un artiste choisi, un influx qui court jusqu'au
/// voisin.
class _Reseau extends CustomPainter {
  _Reseau(this.fils, this.t, {required this.actif, required this.calme});

  final List<_Fil> fils;
  final double t;
  final Color actif;
  final Color calme;

  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final influx = Paint()
      ..color = actif
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final f in fils) {
      final d = f.vers - f.de;
      if (d.distance < 1) continue;
      // Le point de contrôle, un peu de côté : un fil qui ondule, pas une
      // règle. Le côté dépend du fil, il ne change pas.
      final normale = Offset(-d.dy, d.dx) / d.distance;
      final cote = f.phase < 0.5 ? 1.0 : -1.0;
      final ctrl = f.de + d / 2 + normale * (d.distance * 0.12 * cote);
      final chemin = Path()
        ..moveTo(f.de.dx, f.de.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, f.vers.dx, f.vers.dy);
      trait
        ..color = (f.actif ? actif : calme).withValues(
          alpha: (f.actif ? 0.5 : 0.55) * f.opacite,
        )
        ..strokeWidth = f.actif ? 2 : 1.2;
      canvas.drawPath(chemin, trait);
      if (!f.actif) continue;
      // L'influx : un point lumineux, un trajet toutes les 2,2 s environ.
      final p = (t / 2.2 + f.phase) % 1.0;
      final u = 1 - p;
      final pos = f.de * (u * u) + ctrl * (2 * u * p) + f.vers * (p * p);
      influx.color = actif.withValues(alpha: sin(p * pi) * f.opacite);
      canvas.drawCircle(pos, 4, influx);
    }
  }

  @override
  bool shouldRepaint(_Reseau old) => true;
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

import 'package:flutter/material.dart';

import '../../widgets/artwork.dart';

/// Les briques de l'interface à dix pieds.
///
/// Une app de téléviseur n'est pas une app de téléphone en plus grand : il n'y
/// a pas de doigt, il y a une croix directionnelle. **Le curseur, c'est le
/// focus** — et tout le reste en découle : l'élément visé doit se distinguer à
/// trois mètres, rien ne descend sous [tvMinText], et les marges tiennent
/// compte des téléviseurs qui rognent encore les bords.
///
/// Flutter fait déjà le plus dur : sur Android TV les touches de la croix
/// arrivent comme des flèches, que `WidgetsApp` traduit en déplacement de
/// focus, et « OK » comme un `ActivateIntent`. Ce fichier ne fournit donc pas
/// une navigation maison — seulement l'habillage du focus et les rythmes de
/// mise en page.

/// Marges de zone sûre : beaucoup de téléviseurs rognent encore les bords.
const tvSafeH = 90.0;
const tvSafeV = 48.0;

/// Plancher typographique : un 14 px de téléphone est illisible d'un canapé.
const tvMinText = 21.0;

/// Grossissement de l'élément visé.
const _focusScale = 1.09;

/// La place à réserver autour d'une grille ou d'une rangée pour que
/// l'élément visé puisse grandir.
///
/// Un élément grossit de [_focusScale] autour de son centre, et son halo
/// déborde encore un peu. Sans cette marge, la liste le rogne à ses bords :
/// le premier et le dernier d'une rangée se retrouvent tronqués — l'image
/// comme le texte — alors que ceux du milieu, eux, ont la gouttière de leurs
/// voisins pour respirer.
const tvFocusMargin = 26.0;

const _ok = Color(0xFF2FA36B);
const _ko = Color(0xFFE5484D);

/// Le halo qui désigne l'élément visé : liseré blanc net, puis auréole
/// accent. Deux couches plutôt qu'une seule couleur — sur une pochette
/// claire, un halo indigo seul disparaît.
List<BoxShadow> tvFocusGlow(Color accent, {double spread = 6}) => [
  BoxShadow(
    color: accent.withValues(alpha: 0.55),
    blurRadius: spread * 4,
    spreadRadius: spread,
  ),
  const BoxShadow(
    color: Color(0x99000000),
    blurRadius: 40,
    offset: Offset(0, 18),
  ),
];

Border tvFocusBorder(Color accent) =>
    Border.all(color: Colors.white.withValues(alpha: 0.75), width: 3);

/// Coque d'un écran TV : zone sûre, fond transparent (le dégradé du thème vit
/// derrière), et un titre optionnel.
class TvScaffold extends StatelessWidget {
  const TvScaffold({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padSafeArea = true,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;

  /// À couper quand l'écran peint son propre fond jusqu'aux bords (la
  /// pochette floutée de l'écran de lecture, par exemple).
  final bool padSafeArea;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              children: [
                Expanded(child: TvTitle(title!)),
                ?trailing,
              ],
            ),
          ),
        Expanded(child: child),
      ],
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: padSafeArea
          ? Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: tvSafeH,
                vertical: tvSafeV,
              ),
              child: body,
            )
          : body,
    );
  }
}

/// Titre d'écran : 56 px, w800, tracking serré — la signature du design.
class TvTitle extends StatelessWidget {
  const TvTitle(this.text, {super.key, this.size = 56});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -size * 0.03,
      height: 1.02,
    ),
  );
}

/// Intitulé d'une rangée.
class TvShelfLabel extends StatelessWidget {
  const TvShelfLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
    ),
  );
}

/// Enveloppe focalisable commune : gère le focus, l'activation par « OK » et
/// l'habillage. Tout ce qui se vise sur un téléviseur passe par là.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    this.onPressed,
    this.onFocusChange,
    this.autofocus = false,
    this.scale = _focusScale,
    this.focusNode,
  });

  /// Reçoit l'état de focus : à chaque appelant de décider ce qu'il en fait.
  final Widget Function(BuildContext context, bool focused) builder;

  final VoidCallback? onPressed;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final double scale;
  final FocusNode? focusNode;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.onPressed != null,
      // `onFocusChange` et non `onShowFocusHighlight` : ce dernier ne se
      // déclenche qu'une fois le « mode de mise en évidence » passé au
      // clavier, c'est-à-dire après le premier appui sur une touche. Sur un
      // téléviseur, l'élément visé à l'ouverture de l'app serait alors sans
      // halo — et l'écran paraîtrait mort avant qu'on n'y touche.
      onFocusChange: (v) {
        if (v == _focused) return;
        setState(() => _focused = v);
        widget.onFocusChange?.call(v);
      },
      actions: {
        // « OK » de la télécommande arrive comme une activation ; on couvre
        // aussi la barre d'espace et Entrée d'un clavier branché en USB.
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      mouseCursor: SystemMouseCursors.click,
      child: GestureDetector(
        // Certains boîtiers Google TV ont un pavé tactile, et l'émulateur une
        // souris : le clic doit marcher aussi.
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? widget.scale : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: widget.builder(context, _focused),
        ),
      ),
    );
  }
}

/// Une pochette dans une rangée : image, titre, sous-titre. La vignette
/// grossit et s'auréole quand elle est visée, et son titre s'éclaircit.
class TvCard extends StatelessWidget {
  const TvCard({
    super.key,
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.artwork,
    this.size = 250,
    this.round = false,
    this.autofocus = false,
    this.onFocusChange,
    this.icon = Icons.album_rounded,
  });

  final String title;
  final String? subtitle;
  final Widget? artwork;
  final VoidCallback onPressed;
  final double size;

  /// Pastille ronde plutôt que carrée : la forme dit « artiste ».
  final bool round;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = round ? size / 2 : 20.0;

    return SizedBox(
      width: size,
      child: TvFocusable(
        onPressed: onPressed,
        autofocus: autofocus,
        onFocusChange: onFocusChange,
        builder: (context, focused) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: focused ? tvFocusBorder(scheme.primary) : null,
                boxShadow: focused
                    ? tvFocusGlow(scheme.primary)
                    : const [
                        BoxShadow(
                          color: Color(0x80000000),
                          blurRadius: 34,
                          offset: Offset(0, 16),
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child:
                    artwork ??
                    ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        icon,
                        size: size * 0.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.25,
                color: focused ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: tvMinText,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Une rangée qui défile horizontalement et suit le focus.
///
/// Le défilement n'est pas laissé au geste — il n'y en a pas : c'est le focus
/// qui tire la liste, en ramenant la vignette visée à gauche de l'écran. Sans
/// ça, la sixième carte d'une rangée serait inatteignable.
class TvShelf extends StatefulWidget {
  const TvShelf({
    super.key,
    required this.label,
    required this.itemCount,
    required this.itemBuilder,
    this.height = 330,
  });

  final String label;
  final int itemCount;
  final Widget Function(BuildContext context, int index, VoidCallback onFocus)
  itemBuilder;
  final double height;

  @override
  State<TvShelf> createState() => _TvShelfState();
}

class _TvShelfState extends State<TvShelf> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Amène la carte [index] en tête de rangée, un peu en retrait pour qu'on
  /// devine celle d'avant.
  void _bring(int index) {
    if (!_scroll.hasClients) return;
    const stride = 250.0 + 26.0;
    final target = (index * stride - 40 + tvFocusMargin).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TvShelfLabel(widget.label),
        SizedBox(
          // La hauteur comprend la marge de grossissement, en haut comme en
          // bas : sinon la vignette visée se fait couper par la rangée.
          height: widget.height + tvFocusMargin * 2,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            // Le focus décide du défilement : le doigt n'existe pas ici, et
            // laisser la liste défiler seule désynchroniserait les deux.
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(tvFocusMargin),
            itemCount: widget.itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: 26),
            itemBuilder: (context, i) =>
                widget.itemBuilder(context, i, () => _bring(i)),
          ),
        ),
      ],
    );
  }
}

/// Pilule d'action : la signature accent du design, en taille télévision.
class TvPill extends StatelessWidget {
  const TvPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.accent = true,
    this.autofocus = false,
    this.expand = false,
    this.compact = false,
    this.focusNode,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Pour viser ce bouton depuis l'extérieur (ordre de parcours imposé,
  /// tests).
  final FocusNode? focusNode;

  /// Fond accent (l'action principale) ou verre (les secondaires).
  final bool accent;
  final bool autofocus;
  final bool expand;

  /// Version resserrée, pour les formulaires : la pilule pleine taille est
  /// dessinée pour une pochette d'album, pas pour trois lignes de saisie.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      scale: 1.05,
      builder: (context, focused) {
        final bg = accent
            ? scheme.primary
            : Colors.white.withValues(alpha: focused ? 0.18 : 0.08);
        return Container(
          height: compact ? 52 : 66,
          padding: EdgeInsets.symmetric(
            horizontal: icon != null && label.isEmpty
                ? (compact ? 18 : 22)
                : (compact ? 26 : 34),
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(compact ? 26 : 33),
            border: focused
                ? tvFocusBorder(scheme.primary)
                : Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: focused
                ? tvFocusGlow(scheme.primary, spread: 4)
                : accent
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.45),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null)
                Icon(icon, size: compact ? 24 : 30, color: Colors.white),
              if (icon != null && label.isNotEmpty)
                SizedBox(width: compact ? 11 : 14),
              if (label.isNotEmpty)
                // Souple : un libellé long doit se laisser rogner plutôt que
                // de faire déborder la pilule de son panneau.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 21 : 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Panneau de verre, version télévision : mêmes proportions que sur mobile,
/// rayons et ombres à l'échelle du grand écran.
class TvGlass extends StatelessWidget {
  const TvGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = const EdgeInsets.all(28),
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x73000000),
          blurRadius: 60,
          offset: Offset(0, 24),
        ),
      ],
    ),
    child: child,
  );
}

/// Une ligne de piste, à hauteur de téléviseur.
///
/// « En lecture » et « visé » sont deux états distincts qui coexistent : sur
/// mobile on peut les confondre, ici non — on peut parcourir la liste pendant
/// qu'un titre joue.
class TvTrackTile extends StatelessWidget {
  const TvTrackTile({
    super.key,
    required this.index,
    required this.title,
    required this.onPressed,
    this.duration,
    this.subtitle,
    this.playing = false,
    this.autofocus = false,
    this.onFocusChange,
  });

  final int index;
  final String title;
  final String? subtitle;
  final String? duration;
  final bool playing;
  final bool autofocus;
  final VoidCallback onPressed;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      onPressed: onPressed,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      scale: 1.0,
      builder: (context, focused) => Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: focused ? Colors.white.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(16),
          border: focused ? tvFocusBorder(scheme.primary) : null,
          boxShadow: focused ? tvFocusGlow(scheme.primary, spread: 4) : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: playing
                  ? TvEqBars(color: scheme.primary)
                  : Text(
                      '$index',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 23,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
            ),
            const SizedBox(width: 26),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 27,
                      // Interligne fixé : la hauteur d'une ligne de piste ne
                      // doit pas dépendre des métriques de la police, sinon
                      // les 74 px de la rangée débordent.
                      height: 1.15,
                      fontWeight: playing ? FontWeight.w800 : FontWeight.w600,
                      color: playing ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: tvMinText,
                        height: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (duration != null)
              Text(
                duration!,
                style: TextStyle(
                  fontSize: 23,
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Les barres d'égaliseur de la piste en cours — reprises du mobile, en plus
/// grand.
class TvEqBars extends StatefulWidget {
  const TvEqBars({super.key, required this.color, this.height = 26});

  final Color color;
  final double height;

  @override
  State<TvEqBars> createState() => _TvEqBarsState();
}

class _TvEqBarsState extends State<TvEqBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Un téléviseur reste allumé des heures : si l'utilisateur a demandé
    // moins d'animation, on ne fait pas battre des barres indéfiniment.
    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Container(
                width: 5,
                height: still
                    ? widget.height * 0.55
                    : widget.height *
                          (0.3 + 0.7 * ((_c.value + i * 0.25) % 1.0)),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Message d'écran vide, à l'échelle du salon.
class TvEmpty extends StatelessWidget {
  const TvEmpty({
    super.key,
    required this.message,
    this.hint,
    this.icon = Icons.music_off_rounded,
  });

  final String message;
  final String? hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 84,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 22),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 700,
              child: Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bandeau des touches de la télécommande, en bas d'écran.
class TvKeyHints extends StatelessWidget {
  const TvKeyHints({super.key, required this.hints});

  /// Paires « touche → ce qu'elle fait ».
  final List<(String, String)> hints;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final (key, what) in hints) ...[
          Container(
            constraints: const BoxConstraints(minWidth: 38),
            height: 34,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Text(
              key,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Text(
            what,
            style: TextStyle(
              fontSize: tvMinText,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 34),
        ],
      ],
    );
  }
}

/// Pastille d'état colorée (joueurs d'une partie, verdicts).
class TvDot extends StatelessWidget {
  const TvDot({super.key, required this.color, this.size = 18});

  final Color color;
  final double size;

  static const Color ok = _ok;
  static const Color ko = _ko;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Une pochette, à l'échelle du téléviseur.
///
/// Identique à [Artwork], mais demande au serveur une image DÉJÀ réduite :
/// `serve_image.php` rend la source (souvent 1400 px et plus), et un écran
/// d'accueil en charge soixante d'un coup. Sur un boîtier Google TV, c'est
/// autant de mégaoctets à faire transiter et à décoder pour rien.
///
/// La taille demandée est arrondie à une poignée de paliers : le serveur
/// garde une copie par palier, autant qu'elle serve à toutes les vignettes.
class TvArtwork extends StatelessWidget {
  const TvArtwork({
    super.key,
    required this.url,
    this.size,
    this.borderRadius = 10,
    this.icon = Icons.album,
  });

  final String? url;
  final double? size;
  final double borderRadius;
  final IconData icon;

  /// Paliers demandés au serveur (qui plafonne lui-même à 1024).
  static const _steps = [128, 256, 384, 512, 768, 1024];

  static String? sized(String? url, double? size, double dpr) {
    if (url == null || size == null || !url.contains('serve_image.php')) {
      return url;
    }
    final needed = (size * dpr).round();
    final step = _steps.firstWhere((s) => s >= needed, orElse: () => 1024);
    return '$url&size=$step';
  }

  @override
  Widget build(BuildContext context) => Artwork(
    url: sized(url, size, MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0),
    size: size,
    borderRadius: borderRadius,
    icon: icon,
  );
}

/// Compose l'interface sur une toile de 1920 points, puis la met à l'échelle
/// de l'écran réel.
///
/// Un téléviseur 1080p ne rapporte pas 1920 points logiques à Android mais
/// 960 : sa densité vaut 2. Les tailles écrites ici — 56 pour un titre, 250
/// pour une pochette — s'y afficheraient donc deux fois trop grandes, et
/// certains boîtiers en tvdpi donneraient encore un autre résultat.
///
/// Plutôt que de saupoudrer des facteurs dans chaque écran, on compose une
/// bonne fois pour toutes sur une toile de 1920 de large et on la réduit. Une
/// mesure écrite dans le code est ainsi toujours un pixel de téléviseur, quel
/// que soit ce que la boîte raconte — et le rendu du texte suit la
/// transformation, donc rien ne devient flou.
class TvCanvas extends StatelessWidget {
  const TvCanvas({super.key, required this.child});

  /// Largeur de référence : celle du dessin, et celle des mesures du code.
  static const design = 1920.0;

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (!box.hasBoundedWidth || box.maxWidth <= 0) return child;
      final scale = box.maxWidth / design;
      // La hauteur n'est pas forcément en 16/9 (barres système, encoches de
      // certains boîtiers) : on garde celle qu'on a, ramenée à la toile.
      final height = box.hasBoundedHeight
          ? box.maxHeight / scale
          : design * 9 / 16;
      return Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        // `Transform` ne touche qu'à la peinture : sans desserrer les
        // contraintes, l'enfant serait mis en page à la largeur de l'écran
        // puis rétréci — soit une interface deux fois trop petite, collée à
        // gauche. `OverflowBox` lui donne bel et bien la toile.
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: design,
          maxWidth: design,
          minHeight: height,
          maxHeight: height,
          child: SizedBox(width: design, height: height, child: child),
        ),
      );
    },
  );
}

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'album_card.dart' show kArtShadow;
import 'artwork.dart';
import 'adaptive_layout.dart';
import 'glass_kit.dart';

/// L'en-tête des fiches album et artiste.
///
/// Au téléphone, l'image occupe tout le cadre et se dissout vers le bas, le
/// titre en surimpression. C'est ce qui fait ces pages — mais sur un écran
/// large, l'image carrée n'y est plus qu'une mince bande rognée : on ne voit
/// plus la pochette. Passé [kWideLayoutBreakpoint], le même en-tête se
/// réorganise donc : l'image floutée devient une ambiance de couleur (comme
/// derrière le lecteur de la télé), et la pochette nette revient à côté du
/// titre.
///
/// Les deux fiches passent par ici plutôt que de porter chacune sa variante :
/// une seule mise en page à entretenir.
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.imageUrl,
    required this.info,
    required this.onMenu,
    this.icon = Icons.album,
    this.roundCover = false,
  });

  final String? imageUrl;

  /// Le titre et ses lignes secondaires.
  final Widget info;
  final VoidCallback onMenu;

  /// Icône de l'image absente.
  final IconData icon;

  /// Portrait d'artiste : rond, comme partout ailleurs dans l'app.
  final bool roundCover;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final wide = isWideLayout(context);

    final artwork = Artwork(url: imageUrl, borderRadius: 0, icon: icon);

    // L'image se DISSOUT en transparence vers le bas (ShaderMask) : le
    // vrai dégradé de fond de l'app transparaît en continu, sans couleur
    // intermédiaire ni couture.
    Widget backdrop = ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.5, 1.0],
        colors: [Colors.white, Colors.white, Colors.transparent],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: wide
          // Floutée, la bande rognée ne se lit plus comme une image
          // coupée mais comme la couleur de l'album. Elle se dissout
          // aussi sur les côtés : sans ça, elle s'arrêtait net aux bords
          // de la colonne, comme une carte posée sur le fond.
          ? ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                stops: [0.0, 0.14, 0.86, 1.0],
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 40,
                  sigmaY: 40,
                  tileMode: TileMode.decal,
                ),
                child: artwork,
              ),
            )
          : artwork,
    );
    // Le flou déborde de son cadre — de trois fois sa force, ~120 px — et ni
    // le masque (qui n'agit qu'à l'intérieur de son rectangle) ni la pile (qui
    // ne rogne que ses enfants positionnés) ne le retiennent : le coin sombre
    // de la pochette bavait à droite et sous l'en-tête, comme une ombre
    // portée. Au téléphone il n'y a pas de flou, donc rien à rogner.
    if (wide) backdrop = ClipRect(child: backdrop);

    return SizedBox(
      height: wide ? 320 : 440,
      child: Stack(
        fit: StackFit.expand,
        children: [
          backdrop,
          // Voile sombre discret en haut pour la lisibilité du bouton retour.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset + 70,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: topInset + 8,
            child: GlassIconButton(
              icon: Icons.chevron_left,
              tooltip: 'Retour',
              onPressed: () => context.pop(),
            ),
          ),
          Positioned(
            right: 14,
            top: topInset + 8,
            child: GlassIconButton(
              icon: Icons.more_vert,
              tooltip: 'Options',
              onPressed: onMenu,
            ),
          ),
          if (wide)
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        roundCover ? 100 : 18,
                      ),
                      boxShadow: const [kArtShadow],
                    ),
                    child: Artwork(
                      url: imageUrl,
                      size: 200,
                      borderRadius: roundCover ? 100 : 18,
                      icon: icon,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: info),
                ],
              ),
            )
          else
            Positioned(left: 20, right: 20, bottom: 12, child: info),
        ],
      ),
    );
  }
}

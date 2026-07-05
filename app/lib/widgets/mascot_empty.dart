import 'package:flutter/material.dart';

/// État vide signature : la mascotte Gullify + un message. Remplace les
/// « Aucun résultat » nus. La mouette est légèrement désaturée pour se
/// fondre dans le fond sans voler l'attention.
class MascotEmpty extends StatelessWidget {
  const MascotEmpty({
    super.key,
    required this.message,
    this.hint,
    this.action,
    this.size = 132,
  });

  final String message;
  final String? hint;
  final Widget? action;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.9,
              child: ColorFiltered(
                // Léger voile de gris : la mascotte s'intègre au fond.
                colorFilter: const ColorFilter.matrix([
                  0.72, 0.18, 0.10, 0, 0, //
                  0.16, 0.74, 0.10, 0, 0, //
                  0.16, 0.18, 0.66, 0, 0, //
                  0, 0, 0, 1, 0, //
                ]),
                child: Image.asset(
                  'assets/icon/mascot.png',
                  width: size,
                  height: size,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Écran d'ouverture : identique à l'écran de lancement natif (mascotte sur
/// fond perle) pour une transition sans rupture — pas d'animation qui
/// donnerait l'impression d'un deuxième écran.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icon/mascot.png', width: 132),
            const SizedBox(height: 24),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

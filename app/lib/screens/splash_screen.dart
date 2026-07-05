import 'package:flutter/material.dart';

/// Écran d'ouverture Flutter : volontairement minimal. L'écran de lancement
/// natif (mascotte sur perle) fait déjà l'accueil de marque; ici on ne
/// montre qu'un léger indicateur sur le même fond, le temps de restaurer la
/// session — pas un « deuxième splash ».
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}

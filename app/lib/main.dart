import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio/audio_handler.dart';
import 'router.dart';
import 'state/app_theme.dart';
import 'state/equalizer.dart';
import 'state/player.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await initAudioHandler();
  // Ne bloque jamais le premier affichage : l'égaliseur se restaure en
  // arrière-plan et une erreur de plugin ne doit pas geler le démarrage.
  unawaited(applySavedEqualizer(audioHandler).catchError((_) {}));

  // Container indépendant de l'arbre de widgets : quand Android Auto lance
  // l'app sans interface (téléphone verrouillé), aucun widget ne se
  // construit — la liaison auth → repositories du handler doit donc vivre
  // ici, pas dans un écran.
  final container = ProviderContainer(
    overrides: [audioHandlerProvider.overrideWithValue(audioHandler)],
  );
  container.listen(
    audioHandlerBinderProvider,
    (_, _) {},
    fireImmediately: true,
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GullifyApp(),
    ),
  );
}

class GullifyApp extends ConsumerWidget {
  const GullifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentColorProvider);
    return MaterialApp.router(
      title: 'Gullify',
      // Même structure de verre, teintée par l'accent; clair et sombre.
      theme: gullifyThemeFor(accent, dark: false),
      darkTheme: gullifyThemeFor(accent, dark: true),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
      // Fond en dégradé du thème « verre » : les scaffolds y sont
      // transparents, le dégradé vit derrière tout le navigateur.
      builder: (context, child) {
        final surfaces = Theme.of(context).extension<GullifySurfaces>();
        final bg = surfaces?.background;
        if (bg == null || child == null) return child ?? const SizedBox();
        return DecoratedBox(
          decoration: BoxDecoration(gradient: bg),
          child: Stack(
            children: [
              // Halo d'accent diffus (design) : lueur douce en haut d'écran.
              if (surfaces?.accentBlob != null)
                Positioned(
                  top: -140,
                  left: -60,
                  child: Container(
                    width: 420,
                    height: 420,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          surfaces!.accentBlob!.withValues(alpha: 0.16),
                          surfaces.accentBlob!.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              child,
            ],
          ),
        );
      },
    );
  }
}

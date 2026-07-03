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
    final style = ref.watch(themeStyleProvider);
    final system = style == GullifyStyle.system;
    final chosen = system ? null : themeFor(style, Brightness.dark);
    return MaterialApp.router(
      title: 'Gullify',
      theme: chosen ?? gullifyLightTheme(),
      darkTheme: chosen ?? gullifyTheme(),
      themeMode: system ? ThemeMode.system : ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
      // Fond en dégradé du thème « verre » : les scaffolds y sont
      // transparents, le dégradé vit derrière tout le navigateur.
      builder: (context, child) {
        final bg =
            Theme.of(context).extension<GullifySurfaces>()?.background;
        if (bg == null || child == null) return child ?? const SizedBox();
        return DecoratedBox(
          decoration: BoxDecoration(gradient: bg),
          child: child,
        );
      },
    );
  }
}

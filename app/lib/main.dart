import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio/audio_handler.dart';
import 'router.dart';
import 'state/app_theme.dart';
import 'state/player.dart';
import 'theme.dart';
import 'widgets/keyboard_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await initAudioHandler();
  // Ne bloque jamais le premier affichage : l'égaliseur relit ses réglages en
  // arrière-plan et une erreur de plugin ne doit pas geler le démarrage.
  unawaited(audioHandler.equalizer.loadSaved().catchError((_) {}));
  // Idem pour le fondu : d'ici qu'il soit relu, le lecteur fond comme avant.
  unawaited(audioHandler.fade.loadSaved().catchError((_) {}));

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
    UncontrolledProviderScope(container: container, child: const GullifyApp()),
  );
}

class GullifyApp extends ConsumerStatefulWidget {
  const GullifyApp({super.key});

  @override
  ConsumerState<GullifyApp> createState() => _GullifyAppState();
}

class _GullifyAppState extends ConsumerState<GullifyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Trace les passages en arrière-plan / veille dans le journal de lecture,
  // pour les corréler à un éventuel arrêt de la musique écran éteint.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On ne journalise que les transitions utiles au diagnostic : écran
    // allumé / éteint / arrêt de l'app. « inactive » et « hidden » arrivent en
    // rafale (trois lignes par bascule d'écran) et noieraient les événements
    // vraiment importants — pause spontanée, erreur, débranchement.
    final label = switch (state) {
      AppLifecycleState.resumed => 'premier plan (écran allumé)',
      AppLifecycleState.paused => 'arrière-plan (écran éteint ?)',
      AppLifecycleState.detached => 'détaché (arrêt de l\'app)',
      AppLifecycleState.inactive || AppLifecycleState.hidden => null,
    };
    if (label != null) ref.read(audioHandlerProvider).logLifecycle(label);
  }

  @override
  Widget build(BuildContext context) {
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
        // Le garde vit au-dessus du navigateur : il doit survivre aux
        // changements d'écran pour rattraper un inset de clavier resté collé.
        return KeyboardInsetGuard(
          child: DecoratedBox(
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
          ),
        );
      },
    );
  }
}

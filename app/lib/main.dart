import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import 'audio/audio_handler.dart';
import 'router.dart';
import 'state/alarm.dart';
import 'state/app_theme.dart';
import 'state/player.dart';
import 'state/tv.dart';
import 'state/tv_log.dart';
import 'theme.dart';
import 'widgets/keyboard_guard.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/retro_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await initAudioHandler();
  // Ne bloque jamais le premier affichage : l'égaliseur relit ses réglages en
  // arrière-plan et une erreur de plugin ne doit pas geler le démarrage.
  unawaited(audioHandler.equalizer.loadSaved().catchError((_) {}));
  // Idem pour le fondu : d'ici qu'il soit relu, le lecteur fond comme avant.
  unawaited(audioHandler.fade.loadSaved().catchError((_) {}));
  // Le tampon d'avance (idée #90) relit son réglage et retrouve ce qu'il avait
  // déjà descendu — la première file d'une session peut ainsi partir de ce qui
  // est encore sur le disque.
  unawaited(audioHandler.buffer.loadSaved().catchError((_) {}));

  // Téléphone ou téléviseur ? La question se pose une seule fois, ici, avant
  // le premier affichage : le routeur choisit son interface là-dessus, et une
  // réponse qui arriverait après coup ferait clignoter l'app.
  final tv = await detectTelevision();

  if (tv.detected || tv.force == TvForce.tv) {
    // Un boîtier Google TV a rarement plus de 2 Go : les 100 Mo que Flutter
    // réserve par défaut aux images décodées y pèsent trop lourd.
    PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
    // Journal gardé sur le disque : c'est la seule façon de savoir ce qui
    // s'est passé quand l'app a été fermée d'autorité, personne n'allant
    // brancher un ordinateur sur son téléviseur.
    await TvLog.start();
    TvLog.captureErrors();
    TvLog.captureKeys();
    TvLog.add('téléviseur ${tv.detected ? "détecté" : "forcé"}');
  }

  // Container indépendant de l'arbre de widgets : quand Android Auto lance
  // l'app sans interface (téléphone verrouillé), aucun widget ne se
  // construit — la liaison auth → repositories du handler doit donc vivre
  // ici, pas dans un écran.
  final container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWithValue(audioHandler),
      tvDetectedProvider.overrideWithValue(tv.detected),
      tvForceInitialProvider.overrideWithValue(tv.force),
    ],
  );
  container.listen(
    audioHandlerBinderProvider,
    (_, _) {},
    fireImmediately: true,
  );
  // Le réveil (idée #81) vit lui aussi hors de l'arbre de widgets : il doit
  // relire son réglage et reposer son alarme dès le démarrage, même quand
  // l'app est ouverte sans interface (Android Auto), et rattraper une
  // sonnerie qui vient de retentir.
  container.listen(alarmProvider, (_, _) {}, fireImmediately: true);

  // Les shaders du verre d'Apple (idée #105) se compilent au premier affichage
  // sur Android GLES — plusieurs centaines de millisecondes en pleine ouverture
  // d'écran. On les préchauffe donc en arrière-plan, sans jamais retarder le
  // premier affichage : d'ici qu'ils soient prêts, la lentille se peint comme
  // avant. Une erreur de compilation ne doit pas non plus geler le démarrage :
  // AdaptiveGlass sait retomber sur une vitre givrée.
  unawaited(lg.LiquidGlassWidgets.initialize().catchError((_) {}));

  runApp(
    // …et le verre d'Apple doit suivre le clair/sombre CHOISI dans Gullify,
    // pas celui du téléphone : sans ce pont, ses ombres et ses liserés se
    // trompent de mode dès que les deux réglages divergent.
    lg.LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      child: UncontrolledProviderScope(
        container: container,
        child: const GullifyApp(),
      ),
    ),
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
    // Retour au premier plan : une sonnerie a pu retentir pendant que l'app
    // dormait (notification touchée après coup, alarme reçue sans interface).
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(alarmProvider.notifier).checkPending());
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentColorProvider);
    final tv = ref.watch(tvModeProvider);
    // Sur un téléviseur, une seule tête : le verre en sombre. Un salon se
    // regarde dans la pénombre, et ni le rétro Winamp ni le verre d'Apple ne
    // sont dessinés pour être lus à trois mètres.
    final skin = tv ? GullifySkin.glass : ref.watch(skinProvider);
    // Le réveil sonne : l'écran du réveil passe devant tout le reste, quel que
    // soit l'endroit où l'app avait été laissée la veille.
    ref.listen(alarmProvider, (prev, next) {
      if (next.ringing && !(prev?.ringing ?? false)) {
        ref.read(routerProvider).push('/alarm');
      }
    });
    return MaterialApp.router(
      title: 'Gullify',
      // Même structure de verre, teintée par l'accent; clair et sombre. Le
      // rétro Winamp (idée #82), lui, n'a qu'une seule tête : les deux
      // entrées valent alors le même thème, et le mode clair/sombre n'a plus
      // de prise dessus.
      theme: gullifyTheme(skin, accent, dark: tv),
      darkTheme: gullifyTheme(skin, accent, dark: true),
      themeMode: tv ? ThemeMode.dark : ref.watch(themeModeProvider),
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
        // Rétro Winamp : la tôle brossée passe entre le dégradé et les écrans
        // — c'est son grain, plus que le gris, qui fait la façade de 1999
        // (idée #83).
        Widget chassis(Widget child) =>
            (surfaces?.retro ?? false) ? RetroChassis(child: child) : child;
        return KeyboardInsetGuard(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: bg),
            child: chassis(
              Stack(
                children: [
                  // Apple Liquid Glass : le fond d'écran d'iOS (idée #99). Il
                  // REMPLACE les deux halos discrets — c'est lui qui donne au
                  // verre quelque chose à laisser passer, sans quoi la vitre la
                  // plus fine ne rend qu'un gris (« je ne vois même pas la
                  // différence »).
                  if ((surfaces?.liquid ?? false) &&
                      surfaces?.accentBlob != null)
                    Positioned.fill(
                      child: LiquidWallpaper(
                        accent: surfaces!.accentBlob!,
                        dark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    )
                  // Halo d'accent diffus (design) : lueur douce en haut d'écran.
                  else if (surfaces?.accentBlob != null)
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
          ),
        );
      },
    );
  }
}

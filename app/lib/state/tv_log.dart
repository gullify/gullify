import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Journal de bord du téléviseur, **conservé sur le disque**.
///
/// Les journaux déjà en place (Android Auto, lecture) vivent en mémoire :
/// parfaits pour comprendre un comportement, inutiles pour comprendre un
/// plantage — tout part avec le processus. Ici, chaque ligne est écrite au fil
/// de l'eau, et se relit au démarrage suivant depuis
/// Paramètres → Développement → « Journal du téléviseur ».
///
/// On y consigne le fil des écrans (pour savoir *où* ça s'est arrêté) et
/// toute erreur Dart non rattrapée. Un processus tué par manque de mémoire ne
/// laisse, lui, aucune erreur : c'est alors la dernière ligne du fil qui
/// désigne le coupable.
class TvLog {
  TvLog._();

  static const _max = 150;

  static File? _file;
  static final List<String> _lines = <String>[];
  static bool _ready = false;

  /// Écritures sérialisées : deux `add()` rapprochés ne doivent pas se
  /// marcher dessus (le fil des écrans en produit par rafales).
  static Future<void> _tail = Future<void>.value();

  /// Ouvre le journal et relit ce qu'il reste de la session précédente.
  static Future<void> start() async {
    if (_ready) return;
    _ready = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/tv-log.txt');
      if (file.existsSync()) {
        _lines.addAll(await file.readAsLines());
        if (_lines.length > _max) {
          _lines.removeRange(0, _lines.length - _max);
        }
      }
      _file = file;
      add('— démarrage —');
    } catch (_) {
      // Sans disque accessible, le journal reste en mémoire : mieux que rien.
    }
  }

  /// Branche la capture des erreurs Dart non rattrapées.
  ///
  /// On ne remplace pas les gestionnaires existants, on s'y ajoute : couper
  /// celui de Flutter ferait disparaître les messages de la console en
  /// développement.
  static void captureErrors() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      add('ERREUR ${details.exception}');
      final frame = details.stack
          ?.toString()
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      if (frame != null && frame.isNotEmpty) add('   $frame');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      add('ERREUR ASYNC $error');
      return false;
    };
  }

  /// Consigne chaque touche reçue par l'application.
  ///
  /// Sur un téléviseur, savoir si une touche de la croix arrive jusqu'à
  /// Flutter — et sous quel nom — départage en une ligne ce que trois
  /// hypothèses de code ne feront jamais. Le gestionnaire ne consomme jamais
  /// rien : il regarde passer.
  static void captureKeys() {
    HardwareKeyboard.instance.addHandler((event) {
      if (event is KeyDownEvent) {
        add(
          'touche ${event.logicalKey.keyLabel.isEmpty ? event.logicalKey.debugName ?? event.logicalKey : event.logicalKey.keyLabel}',
        );
      }
      return false;
    });
  }

  /// Ajoute une ligne horodatée. Ne lève jamais et n'attend rien : le journal
  /// ne doit pas peser sur ce qu'il observe.
  static void add(String message) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final line = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $message';
    _lines.add(line);
    if (_lines.length > _max) _lines.removeAt(0);
    if (kDebugMode) debugPrint('[Gullify][TV] $message');

    final file = _file;
    if (file == null) return;
    _tail = _tail.then((_) async {
      try {
        await file.writeAsString('${_lines.join('\n')}\n');
      } catch (_) {}
    });
  }

  /// Le journal, du plus récent au plus ancien (comme les autres écrans de
  /// diagnostic de l'app).
  static List<String> get lines => _lines.reversed.toList(growable: false);

  static Future<void> clear() async {
    _lines.clear();
    try {
      await _file?.writeAsString('');
    } catch (_) {}
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Les plantages de l'app, envoyés à l'atelier (point d'accueil `rapport.php?app=gullify`).
///
/// Seulement : la version, la plateforme, la CLASSE de l'erreur et les premières lignes de la pile.
/// Jamais le message de l'erreur : il peut contenir une adresse de flux ou un jeton.
/// L'envoi est en arrière-plan, sans attente, et un échec n'en provoque jamais un autre.
const _versionApp = '3.85.0';
const _adresse = 'https://gullify.app/api/v2/rapport.php?app=gullify';

final _envoi = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 8),
  sendTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 8),
  headers: {'Content-Type': 'text/plain; charset=utf-8'},
));

bool _envoyeEnCours = false;

/// À appeler une fois, au démarrage, après `WidgetsFlutterBinding.ensureInitialized()`.
void installerRapportsPlantage() {
  final precedent = FlutterError.onError;
  FlutterError.onError = (details) {
    precedent?.call(details);
    _rapporter(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (erreur, pile) {
    _rapporter(erreur, pile);
    return true;
  };
}

void _rapporter(Object erreur, StackTrace? pile) {
  if (_envoyeEnCours) return; // jamais une boucle : un rapport qui plante ne se renvoie pas
  _envoyeEnCours = true;
  final lignes = (pile?.toString() ?? '').split('\n').take(6).join('\n');
  final texte = StringBuffer()
    ..writeln('Gullify-plantage v1')
    ..writeln('version: $_versionApp')
    ..writeln('plateforme: ${_plateforme()}')
    ..writeln('erreur: ${erreur.runtimeType}')
    ..writeln('pile:')
    ..write(lignes);
  unawaited(_envoyer(texte.toString()));
}

Future<void> _envoyer(String texte) async {
  try {
    await _envoi.post<dynamic>(_adresse, data: texte);
  } catch (_) {
    // Hors ligne ou serveur absent : tant pis, on ne doit jamais planter en signalant un plantage.
  } finally {
    _envoyeEnCours = false;
  }
}

String _plateforme() {
  if (kIsWeb) return 'web';
  try {
    return Platform.operatingSystem;
  } catch (_) {
    return 'inconnue';
  }
}

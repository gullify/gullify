import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Le mode « dossier local » (idée #114) noté en clair, à côté du coffre.
///
/// Android Auto ouvre l'app sans interface, et pose sa première question — que
/// contient la racine ? — avant que le coffre chiffré n'ait rendu l'adresse du
/// serveur. Le lecteur répondait alors le menu du serveur dans un mode qui n'en
/// a pas : la voiture partait attendre une bibliothèque que personne n'allait
/// servir, et cherchait sans fin (idée #115).
///
/// Ce marqueur-ci se lit en une ouverture de fichier, comme la reprise : au
/// démarrage, le lecteur sait tout de suite s'il y a un serveur à attendre. Un
/// chemin de dossier n'est pas un secret — contrairement au jeton, il n'a pas
/// besoin du coffre pour être bien gardé.
class LocalModeFlag {
  const LocalModeFlag._();

  /// Le dossier, imposé par les tests (pas de path_provider hors téléphone).
  @visibleForTesting
  static Directory? dirForTest;

  static Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = dirForTest ?? await getApplicationDocumentsDirectory();
      return File('${dir.path}/local_mode.json');
    } catch (_) {
      // Pas de dossier (plugin absent hors téléphone) : le marqueur n'existe
      // pas, l'app repart du coffre comme avant.
      return null;
    }
  }

  /// Le dossier de musique retenu, ou `null` : pas de mode local.
  static Future<String?> read() async {
    try {
      final f = await _file();
      if (f == null || !f.existsSync()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final folder = j['folder'] as String?;
      return (folder == null || folder.isEmpty) ? null : folder;
    } catch (_) {
      // Marqueur illisible : on s'en remet au coffre.
      return null;
    }
  }

  /// Retient le dossier, ou efface le marqueur ([folder] nul) quand on repasse
  /// au serveur.
  static Future<void> write(String? folder) async {
    try {
      final f = await _file();
      if (f == null) return;
      if (folder == null || folder.isEmpty) {
        if (f.existsSync()) await f.delete();
        return;
      }
      await f.writeAsString(jsonEncode({'folder': folder}));
    } catch (_) {
      // Marqueur non écrit : le coffre reste la source, le lecteur attendra
      // simplement la session comme avant.
    }
  }
}

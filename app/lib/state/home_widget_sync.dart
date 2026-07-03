import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import 'player.dart';

/// Pousse la piste en cours (titre, artiste, pochette, lecture/pause) vers
/// le widget Android. Meilleur effort : jamais bloquant, jamais d'erreur UI.
final homeWidgetSyncProvider = Provider<void>((ref) {
  if (kIsWeb || !Platform.isAndroid) return;

  String? lastArtUrl;
  String? artPath;

  Future<void> push() async {
    final item = ref.read(currentMediaItemProvider).value;
    final playing =
        ref.read(playbackStateProvider).value?.playing ?? false;
    try {
      final artUrl = item?.artUri?.toString();
      if (artUrl != lastArtUrl) {
        lastArtUrl = artUrl;
        artPath = null;
        if (artUrl != null) {
          final dir = await getApplicationCacheDirectory();
          final path = '${dir.path}/widget_art.png';
          await Dio().download(artUrl, path);
          artPath = path;
        }
      }
      await HomeWidget.saveWidgetData<String>('title', item?.title ?? '');
      await HomeWidget.saveWidgetData<String>('artist', item?.artist ?? '');
      await HomeWidget.saveWidgetData<bool>('playing', playing);
      await HomeWidget.saveWidgetData<String>('artPath', artPath ?? '');
      await HomeWidget.updateWidget(androidName: 'GullifyWidgetProvider');
    } catch (_) {
      // Widget absent ou pochette inaccessible : sans conséquence.
    }
  }

  ref.listen(currentMediaItemProvider, (_, _) => push());
  ref.listen(playbackStateProvider, (prev, next) {
    if (prev?.value?.playing != next.value?.playing) push();
  });
});

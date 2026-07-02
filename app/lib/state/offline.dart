import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'library.dart';

bool get offlineSupported => !kIsWeb;

class OfflineSong {
  const OfflineSong({
    required this.song,
    required this.localPath,
    required this.size,
  });

  factory OfflineSong.fromJson(Map<String, dynamic> j) => OfflineSong(
        song: Song.fromJson(j['song'] as Map<String, dynamic>),
        localPath: j['localPath'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
      );

  final Song song;
  final String localPath;
  final int size;

  Map<String, dynamic> toJson() => {
        'song': song.toJson(),
        'localPath': localPath,
        'size': size,
      };
}

/// Downloaded songs, keyed by song id. Index persisted as JSON next to the
/// audio files in `<documents>/offline/`.
class OfflineManager extends AsyncNotifier<Map<int, OfflineSong>> {
  Directory? _dir;

  Future<Directory> _offlineDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/offline');
    await d.create(recursive: true);
    return _dir = d;
  }

  File _indexFile(Directory d) => File('${d.path}/index.json');

  @override
  Future<Map<int, OfflineSong>> build() async {
    if (!offlineSupported) return {};
    final f = _indexFile(await _offlineDir());
    if (!f.existsSync()) return {};
    try {
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      return {
        for (final e in list.map(
          (e) => OfflineSong.fromJson(e as Map<String, dynamic>),
        ))
          if (File(e.localPath).existsSync()) e.song.id: e,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _commit(Map<int, OfflineSong> map) async {
    final d = await _offlineDir();
    await _indexFile(d).writeAsString(
      jsonEncode([for (final o in map.values) o.toJson()]),
    );
    state = AsyncData(map);
  }

  Future<void> download(Song song) async {
    if (!offlineSupported) return;
    final current = Map<int, OfflineSong>.of(state.value ?? {});
    if (current.containsKey(song.id)) return;

    final d = await _offlineDir();
    final dot = song.filePath.lastIndexOf('.');
    final ext = dot >= 0 ? song.filePath.substring(dot + 1) : 'mp3';
    final path = '${d.path}/${song.id}.$ext';
    final url = ref.read(libraryRepositoryProvider).streamUrl(song);
    await Dio().download(url, path);

    current[song.id] = OfflineSong(
      song: song,
      localPath: path,
      size: File(path).lengthSync(),
    );
    await _commit(current);
  }

  Future<void> downloadAll(List<Song> songs) async {
    for (final s in songs) {
      await download(s);
    }
  }

  Future<void> remove(int songId) async {
    final current = Map<int, OfflineSong>.of(state.value ?? {});
    final removed = current.remove(songId);
    if (removed != null) {
      try {
        await File(removed.localPath).delete();
      } catch (_) {}
    }
    await _commit(current);
  }

  Future<void> clear() async {
    final current = state.value ?? {};
    for (final o in current.values) {
      try {
        await File(o.localPath).delete();
      } catch (_) {}
    }
    await _commit({});
  }

  int totalSize() => (state.value?.values ?? const Iterable<OfflineSong>.empty())
      .fold(0, (sum, o) => sum + o.size);
}

final offlineProvider =
    AsyncNotifierProvider<OfflineManager, Map<int, OfflineSong>>(
  OfflineManager.new,
);

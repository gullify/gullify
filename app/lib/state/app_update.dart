import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Manifest de mise à jour publié sur download.gullify.app.
/// Partagé avec l'auto-updater de l'ancienne app : versionCode global,
/// toujours croissant, indépendant du package installé.
const updateManifestUrl = 'https://download.gullify.app/version.json';

class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    this.changelog,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        versionCode: (json['versionCode'] as num).toInt(),
        versionName: json['versionName'] as String,
        downloadUrl: json['downloadUrl'] as String,
        changelog: json['changelog'] as String?,
      );

  final int versionCode;
  final String versionName;
  final String downloadUrl;
  final String? changelog;
}

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  error,
}

class AppUpdateState {
  const AppUpdateState({
    this.status = UpdateStatus.idle,
    this.available,
    this.progress,
    this.apkPath,
    this.message,
    this.currentVersion = '',
  });

  final UpdateStatus status;
  final UpdateInfo? available;

  /// Progression du téléchargement, 0..1 (null si taille inconnue).
  final double? progress;
  final String? apkPath;
  final String? message;
  final String currentVersion;

  AppUpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? available,
    double? progress,
    String? apkPath,
    String? message,
    String? currentVersion,
  }) =>
      AppUpdateState(
        status: status ?? this.status,
        available: available ?? this.available,
        progress: progress ?? this.progress,
        apkPath: apkPath ?? this.apkPath,
        message: message ?? this.message,
        currentVersion: currentVersion ?? this.currentVersion,
      );
}

class AppUpdateNotifier extends Notifier<AppUpdateState> {
  // Client dédié : version.json vit sur download.gullify.app, hors API v2,
  // sans auth ni envelope.
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  @override
  AppUpdateState build() => const AppUpdateState();

  /// Vérifie si une mise à jour est disponible.
  ///
  /// [silent] : en cas d'échec réseau (démarrage sans connexion, serveur de
  /// download injoignable), retombe sur idle sans afficher d'erreur.
  Future<void> check({bool silent = false}) async {
    if (!Platform.isAndroid) return;
    final info = await PackageInfo.fromPlatform();
    final current = int.tryParse(info.buildNumber) ?? 0;
    state = state.copyWith(
      status: UpdateStatus.checking,
      currentVersion: info.version,
    );
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        updateManifestUrl,
        options: Options(responseType: ResponseType.json),
      );
      final update = UpdateInfo.fromJson(r.data!);
      if (update.versionCode > current) {
        state = state.copyWith(
          status: UpdateStatus.available,
          available: update,
        );
      } else {
        state = state.copyWith(status: UpdateStatus.upToDate);
      }
    } catch (e) {
      state = state.copyWith(
        status: silent ? UpdateStatus.idle : UpdateStatus.error,
        message: 'Impossible de vérifier les mises à jour',
      );
    }
  }

  Future<void> _download(String url, String path) {
    var lastPct = -1;
    return _dio.download(
      url,
      path,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        if (total <= 0) return;
        final pct = (received * 100 ~/ total);
        if (pct != lastPct) {
          lastPct = pct;
          state = state.copyWith(progress: pct / 100);
        }
      },
    );
  }

  /// Télécharge l'APK puis ouvre l'installeur système.
  Future<void> downloadAndInstall() async {
    final update = state.available;
    if (update == null) return;
    state = state.copyWith(status: UpdateStatus.downloading, progress: 0);
    try {
      final dir = await getApplicationCacheDirectory();
      final path = '${dir.path}/gullify-update.apk';
      try {
        await _download(update.downloadUrl, path);
      } catch (_) {
        // Repli : le lien « latest » pointe toujours sur la dernière version.
        await _download('https://download.gullify.app/gullify-latest.apk', path);
      }
      state = state.copyWith(
        status: UpdateStatus.readyToInstall,
        apkPath: path,
      );
      await install();
    } catch (e) {
      // Affiche la cause réelle : indispensable pour diagnostiquer à distance.
      final detail = e is DioException
          ? '${e.type.name}${e.response != null ? ' HTTP ${e.response!.statusCode}' : ''}'
              '${e.message != null ? ' — ${e.message}' : ''}'
          : '$e';
      state = state.copyWith(
        status: UpdateStatus.error,
        message: 'Échec du téléchargement : $detail',
      );
    }
  }

  /// (Re)lance l'installeur sur l'APK déjà téléchargé — utile si
  /// l'utilisateur a refusé la permission "sources inconnues" au 1er essai.
  /// Canal natif maison (MainActivity) : FileProvider + intent ACTION_VIEW.
  Future<void> install() async {
    final path = state.apkPath;
    if (path == null) return;
    try {
      await const MethodChannel('gullify/installer')
          .invokeMethod<bool>('installApk', {'path': path});
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        message: "Impossible de lancer l'installation : $e",
      );
    }
  }

  void dismiss() {
    if (state.status == UpdateStatus.available ||
        state.status == UpdateStatus.error) {
      state = state.copyWith(status: UpdateStatus.idle);
    }
  }
}

final appUpdateProvider =
    NotifierProvider<AppUpdateNotifier, AppUpdateState>(AppUpdateNotifier.new);

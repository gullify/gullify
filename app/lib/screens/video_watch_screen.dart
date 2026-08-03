import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../state/player.dart';
import '../state/videos.dart';

/// Lecture d'une vidéo (clip, concert, live).
///
/// Le flux vient toujours du serveur : soit le fichier téléchargé, soit un
/// relais du flux YouTube (les URL YouTube sont liées à l'IP qui les résout).
/// La musique en cours est mise en pause à l'ouverture — deux sons en même
/// temps n'ont aucun sens.
class VideoWatchScreen extends ConsumerStatefulWidget {
  const VideoWatchScreen({
    super.key,
    required this.videoId,
    required this.title,
  });

  final String videoId;
  final String title;

  @override
  ConsumerState<VideoWatchScreen> createState() => _VideoWatchScreenState();
}

class _VideoWatchScreenState extends ConsumerState<VideoWatchScreen> {
  VideoPlayerController? _controller;
  String? _error;
  bool _controlsVisible = true;
  bool _landscape = false;
  Timer? _hideControls;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    // La musique d'abord : la vidéo prend la main sur le son.
    try {
      await ref.read(audioHandlerProvider).pause();
    } catch (_) {}

    final url = ref.read(videosRepositoryProvider).streamUrl(widget.videoId);
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: ref.read(videoStreamHeadersProvider),
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      setState(() => _controller = controller);
      await controller.play();
      unawaited(WakelockPlus.toggle(enable: true));
      _scheduleHide();
    } catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
      _hideControls?.cancel();
      setState(() => _controlsVisible = true);
    } else {
      await c.play();
      _scheduleHide();
    }
    unawaited(WakelockPlus.toggle(enable: c.value.isPlaying));
  }

  Future<void> _toggleLandscape() async {
    final next = !_landscape;
    setState(() => _landscape = next);
    await SystemChrome.setPreferredOrientations(
      next
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : DeviceOrientation.values,
    );
    await SystemChrome.setEnabledSystemUIMode(
      next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    unawaited(WakelockPlus.toggle(enable: false));
    // Toujours rendre l'orientation et les barres système à l'app.
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: switch ((controller, _error)) {
              (_, final String e) => _Failure(message: e),
              (final VideoPlayerController c, _) => AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
              _ => const CircularProgressIndicator(),
            },
          ),
          // Zone de tap : dévoile/masque les commandes.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              child: const SizedBox.expand(),
            ),
          ),
          AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: _Controls(
                title: widget.title,
                controller: controller,
                landscape: _landscape,
                onPlayPause: _togglePlay,
                onToggleLandscape: _toggleLandscape,
                onBack: () => context.pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.title,
    required this.controller,
    required this.landscape,
    required this.onPlayPause,
    required this.onToggleLandscape,
    required this.onBack,
  });

  final String title;
  final VideoPlayerController? controller;
  final bool landscape;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleLandscape;
  final VoidCallback onBack;

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final value = controller?.value;
    final position = value?.position ?? Duration.zero;
    final total = value?.duration ?? Duration.zero;

    return Container(
      // Voile haut et bas : le texte reste lisible sur toutes les images.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
          stops: const [0, 0.4, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: onBack,
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: landscape ? 'Quitter le plein écran' : 'Plein écran',
                  icon: Icon(
                    landscape
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                  onPressed: onToggleLandscape,
                ),
              ],
            ),
            const Spacer(),
            if (value != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      iconSize: 34,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                      onPressed: onPlayPause,
                    ),
                    Text(
                      _fmt(position),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: total.inMilliseconds == 0
                            ? 0
                            : position.inMilliseconds
                                  .clamp(0, total.inMilliseconds)
                                  .toDouble(),
                        // Une durée nulle (flux en direct) donnerait max == min.
                        max: total.inMilliseconds.clamp(1, 1 << 31).toDouble(),
                        onChanged: (v) => controller?.seekTo(
                          Duration(milliseconds: v.round()),
                        ),
                      ),
                    ),
                    Text(
                      _fmt(total),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 44),
        const SizedBox(height: 12),
        const Text(
          'Lecture impossible',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 12.5),
        ),
      ],
    ),
  );
}

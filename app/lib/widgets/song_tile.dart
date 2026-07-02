import 'package:flutter/material.dart';

import '../models/song.dart';
import 'artwork.dart';

String formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onLongPress,
    this.showArtwork = true,
    this.leadingNumber,
    this.isPlaying = false,
    this.subtitle,
    this.trailing,
  });

  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showArtwork;
  final int? leadingNumber;
  final bool isPlaying;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: showArtwork
          ? Artwork(url: song.artworkUrl, size: 44, icon: Icons.music_note)
          : SizedBox(
              width: 32,
              child: Center(
                child: isPlaying
                    ? Icon(Icons.graphic_eq, size: 18, color: scheme.primary)
                    : Text(
                        '${leadingNumber ?? ''}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
              ),
            ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isPlaying
            ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)
            : null,
      ),
      subtitle: (subtitle ?? song.artistName) != null
          ? Text(
              subtitle ?? song.artistName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: trailing ??
          Text(
            formatDuration(song.duration),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
    );
  }
}

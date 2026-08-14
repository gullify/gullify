import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/share_repository.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/song.dart';
import '../state/shares.dart';
import 'artwork.dart';
import 'glass_kit.dart';

/// Ce qu'on s'apprête à partager : une chanson, un album, un artiste.
///
/// Seuls [kind] et [id] partent au serveur — le reste ne sert qu'à montrer,
/// dans la feuille, ce qu'on est en train de partager.
class ShareTarget {
  const ShareTarget({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.artworkUrl,
  });

  ShareTarget.song(Song song)
    : kind = ShareKind.song,
      id = song.id,
      title = song.title,
      subtitle = song.artistName,
      artworkUrl = song.artworkUrl;

  ShareTarget.album(Album album)
    : kind = ShareKind.album,
      id = album.id,
      title = album.name,
      subtitle = album.artistName,
      artworkUrl = album.artworkUrl;

  ShareTarget.artist(Artist artist)
    : kind = ShareKind.artist,
      id = artist.id,
      title = artist.name,
      subtitle = null,
      artworkUrl = artist.imageUrl;

  final ShareKind kind;
  final int id;
  final String title;
  final String? subtitle;
  final String? artworkUrl;

  /// L'icône de remplacement quand il n'y a pas d'image.
  IconData get icon => switch (kind) {
    ShareKind.song => Icons.music_note,
    ShareKind.album => Icons.album_outlined,
    ShareKind.artist => Icons.person_outline,
  };

  /// Le message qu'on propose d'envoyer, tourné selon ce qu'on partage.
  String smsBody(String url) {
    final who = subtitle == null ? '' : ' de $subtitle';
    return switch (kind) {
      ShareKind.song => 'Écoute « $title »$who sur Gullify : $url',
      ShareKind.album => 'Écoute l\'album « $title »$who sur Gullify : $url',
      ShareKind.artist => 'Écoute $title sur Gullify : $url',
    };
  }
}

/// Feuille « Partager » : un lien d'écoute vers une chanson, un album ou un
/// artiste, valable 24 h, à envoyer comme on envoie une invitation à une
/// partie.
///
/// Le lien est demandé au serveur dès l'ouverture de la feuille : c'est lui
/// qui tire le jeton et qui fixe l'échéance, l'app ne fait que le présenter.
/// « Désactiver le lien » le coupe avant l'heure, pour quand on se ravise.
Future<void> showShareSheet(BuildContext context, ShareTarget target) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => _ShareSheet(target: target),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.target});

  final ShareTarget target;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  SongShareLink? _link;
  String? _error;
  bool _revoking = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    setState(() => _error = null);
    try {
      final link = await ref
          .read(shareRepositoryProvider)
          .create(widget.target.kind, widget.target.id);
      if (mounted) setState(() => _link = link);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Le lien n\'a pas pu être créé');
      }
    }
  }

  Future<void> _sms(String url) async {
    final body = Uri.encodeComponent(widget.target.smsBody(url));
    final messenger = ScaffoldMessenger.of(context);
    if (!await launchUrl(Uri.parse('sms:?body=$body'))) {
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(
        const SnackBar(content: Text('Lien copié — colle-le dans un message')),
      );
    }
  }

  Future<void> _revoke(String token) async {
    setState(() => _revoking = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(shareRepositoryProvider).revoke(token);
      messenger.showSnackBar(
        const SnackBar(content: Text('Lien désactivé')),
      );
      navigator.pop();
    } catch (_) {
      if (mounted) {
        setState(() => _revoking = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Le lien n\'a pas pu être désactivé')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = widget.target;
    final link = _link;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Artwork(
                  url: target.artworkUrl,
                  size: 56,
                  icon: target.icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.3,
                        ),
                      ),
                      if (target.subtitle != null)
                        Text(
                          target.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null)
              _Message(
                icon: Icons.link_off_rounded,
                text: _error!,
                action: TextButton(
                  onPressed: _create,
                  child: const Text('Réessayer'),
                ),
              )
            else if (link == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _Ready(
                link: link,
                revoking: _revoking,
                onSms: () => _sms(link.url),
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: link.url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lien copié')),
                  );
                },
                onRevoke: () => _revoke(link.token),
              ),
          ],
        ),
      ),
    );
  }
}

/// Le lien est ouvert : on le montre, on l'envoie, ou on le coupe.
class _Ready extends StatelessWidget {
  const _Ready({
    required this.link,
    required this.revoking,
    required this.onSms,
    required this.onCopy,
    required this.onRevoke,
  });

  final SongShareLink link;
  final bool revoking;
  final VoidCallback onSms;
  final VoidCallback onCopy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Un album ou un artiste s'écoute d'affilée : on annonce combien de titres
    // le lien ouvre, pour qu'on sache ce qu'on envoie.
    final what = link.trackCount > 1
        ? '${link.trackCount} titres, écoutables'
        : 'Écoutable';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          link.url,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          '$what sans compte, puis le lien s\'efface dans '
          '${link.remainingLabel}.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        AccentPlayButton(
          label: 'Envoyer par SMS',
          icon: Icons.sms_rounded,
          expand: true,
          onPressed: revoking ? null : onSms,
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: revoking ? null : onCopy,
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('Copier le lien'),
        ),
        TextButton.icon(
          onPressed: revoking ? null : onRevoke,
          icon: const Icon(Icons.link_off_rounded, size: 18),
          label: const Text('Désactiver le lien'),
          style: TextButton.styleFrom(foregroundColor: scheme.error),
        ),
      ],
    );
  }
}

/// Échec de création : le message du serveur et de quoi réessayer.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(icon, size: 32, color: scheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          ?action,
        ],
      ),
    );
  }
}

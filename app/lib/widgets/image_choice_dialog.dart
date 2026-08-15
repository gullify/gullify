import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import 'artwork.dart';

/// Une image que YouTube Music ou Deezer propose (photo d'artiste — idée #78,
/// jaquette d'album — idée #93).
///
/// Le [label] et le [sublabel] sont ceux du SERVICE, pas ceux de la
/// bibliothèque : c'est à eux qu'on voit qu'on tient l'homonyme, la
/// compilation ou la réédition plutôt que ce qu'on cherchait.
class ImageCandidate {
  const ImageCandidate({
    required this.thumbnail,
    required this.label,
    this.sublabel,
    required this.source,
  });

  final String thumbnail;
  final String label;
  final String? sublabel;

  /// `ytmusic` ou `deezer`.
  final String source;
}

/// Choisir une image à la main : une proposition de YouTube Music ou de
/// Deezer, un lien collé, ou une image du téléphone — et de quoi défaire son
/// choix pour revenir à ce que le serveur trouve tout seul.
///
/// Le dialogue ne connaît ni artiste ni album : il reçoit de quoi chercher et
/// de quoi enregistrer. Il se referme en rendant le message à afficher, ou
/// null si rien n'a changé.
class ImageChoiceDialog extends StatefulWidget {
  const ImageChoiceDialog({
    super.key,
    required this.title,
    required this.searchLabel,
    required this.initialQuery,
    required this.onSearch,
    required this.onUrl,
    required this.onFile,
    required this.onReset,
    required this.resetLabel,
    required this.doneMessage,
    required this.resetMessage,
    required this.emptyMessage,
    this.round = false,
    this.placeholderIcon = Icons.album,
  });

  /// Titre du dialogue (« Image de « … » », « Jaquette de « … » »).
  final String title;

  /// Libellé du champ de recherche, et texte cherché à l'ouverture.
  final String searchLabel;
  final String initialQuery;

  final Future<List<ImageCandidate>> Function(String query) onSearch;

  /// Enregistre l'image qui se trouve à cette adresse.
  final Future<void> Function(String url) onUrl;

  /// Enregistre une image prise dans la galerie du téléphone.
  final Future<void> Function(String filePath) onFile;

  /// Défait le choix manuel.
  final Future<void> Function() onReset;

  final String resetLabel;

  /// Ce que le dialogue rend selon ce qui a été fait.
  final String doneMessage;
  final String resetMessage;

  /// Ce qui s'affiche quand les services n'ont rien sous ce nom.
  final String emptyMessage;

  /// Vignettes rondes (une photo d'artiste) ou carrées (une jaquette).
  final bool round;
  final IconData placeholderIcon;

  @override
  State<ImageChoiceDialog> createState() => _ImageChoiceDialogState();
}

class _ImageChoiceDialogState extends State<ImageChoiceDialog> {
  late final _searchCtrl = TextEditingController(text: widget.initialQuery);
  final _linkCtrl = TextEditingController();

  /// La recherche en cours. Elle part à l'ouverture : arriver sur une liste
  /// vide à remplir soi-même serait un tap de trop pour le cas courant.
  late Future<List<ImageCandidate>> _candidates =
      widget.onSearch(widget.initialQuery);

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  void _runSearch() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _error = null;
      _candidates = widget.onSearch(q);
    });
  }

  /// Enregistre, puis referme en disant ce qui a été fait. Un échec reste
  /// dans le dialogue : l'image n'a pas changé, autant pouvoir réessayer
  /// sans tout rouvrir.
  Future<void> _apply(Future<void> Function() work, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
      if (mounted) Navigator.pop(context, done);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : '$e';
      });
    }
  }

  void _useUrl(String url) =>
      _apply(() => widget.onUrl(url), widget.doneMessage);

  Future<void> _pickFile() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
      maxHeight: 1000,
    );
    if (picked == null || !mounted) return;
    await _apply(() => widget.onFile(picked.path), widget.doneMessage);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 380,
        child: _busy
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Envoi de l\'image…'),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Le texte cherché se change : quand l'image trouvée est
                  // celle d'un homonyme, c'est ici qu'on rattrape le tir.
                  TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 14),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: widget.searchLabel,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: 'Chercher',
                        onPressed: _runSearch,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: FutureBuilder<List<ImageCandidate>>(
                        future: _candidates,
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Column(
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 10),
                                    Text(
                                      'YouTube Music et Deezer…',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final list = snap.data ?? const [];
                          if (list.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                snap.hasError
                                    ? 'Recherche impossible pour le moment.'
                                    : widget.emptyMessage,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final c in list)
                                _CandidateTile(
                                  candidate: c,
                                  round: widget.round,
                                  placeholderIcon: widget.placeholderIcon,
                                  onTap: () => _useUrl(c.thumbnail),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 20),
                  // Ce que ni YouTube ni Deezer n'ont : un lien trouvé
                  // ailleurs, ou une image prise soi-même.
                  TextField(
                    controller: _linkCtrl,
                    style: const TextStyle(fontSize: 14),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) _useUrl(v.trim());
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Coller un lien',
                      hintText: 'https://…',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check),
                        tooltip: 'Utiliser ce lien',
                        onPressed: () {
                          final url = _linkCtrl.text.trim();
                          if (url.isNotEmpty) _useUrl(url);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choisir une image'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 13, color: scheme.error),
                      ),
                    ),
                ],
              ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: [
        // Défaire son choix : ce que le serveur trouve tout seul (dossier,
        // tags, web) reprend la main.
        TextButton(
          style: compactDialogAction,
          onPressed: _busy
              ? null
              : () => _apply(widget.onReset, widget.resetMessage),
          child: Text(widget.resetLabel),
        ),
        TextButton(
          style: compactDialogAction,
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

/// Boutons d'action serrés : les dialogues de choix en portent trois de front.
const compactDialogAction = ButtonStyle(
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
  textStyle: WidgetStatePropertyAll(
    TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  ),
  visualDensity: VisualDensity.compact,
);

/// Une image proposée : la vignette, ce que le service en dit, et d'où elle
/// vient — c'est ce libellé qui trahit l'homonyme ou la compilation.
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.round,
    required this.placeholderIcon,
    required this.onTap,
  });

  final ImageCandidate candidate;
  final bool round;
  final IconData placeholderIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 104,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Artwork(
              url: candidate.thumbnail,
              size: 96,
              borderRadius: round ? 48 : 12,
              icon: placeholderIcon,
            ),
            const SizedBox(height: 6),
            Text(
              candidate.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (candidate.sublabel != null && candidate.sublabel!.isNotEmpty)
              Text(
                candidate.sublabel!,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            Text(
              candidate.source == 'deezer' ? 'Deezer' : 'YouTube Music',
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

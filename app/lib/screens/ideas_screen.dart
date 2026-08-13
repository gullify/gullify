import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/ideas_repository.dart';
import '../state/auth.dart';
import '../state/ideas.dart';

/// Carnet d'idées de développement : ajout rapide + liste cochable.
/// Partagé avec Claude (lit/écrit les mêmes idées côté serveur).
///
/// Chaque idée peut porter des pièces jointes (idée #84) : une capture de ce
/// qui cloche vaut mieux qu'un paragraphe, et Claude les lit avant de coder.
class IdeasScreen extends ConsumerStatefulWidget {
  const IdeasScreen({super.key, this.filePicker});

  /// Sélecteur de fichiers injectable : ni galerie ni SAF sous test.
  final Future<List<PickedIdeaFile>> Function()? filePicker;

  @override
  ConsumerState<IdeasScreen> createState() => _IdeasScreenState();
}

/// Un fichier choisi sur le téléphone, pas encore envoyé (idée pas créée).
class PickedIdeaFile {
  const PickedIdeaFile(this.path, this.name);

  final String path;
  final String name;

  bool get isImage => mimeForName(name).startsWith('image/');
}

class _IdeasScreenState extends ConsumerState<IdeasScreen> {
  final _controller = TextEditingController();
  final List<PickedIdeaFile> _pending = [];
  bool _adding = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Rafraîchit périodiquement pour voir avancer les idées confiées à Claude.
    _poll = Timer.periodic(
      const Duration(seconds: 12),
      (_) => mounted ? ref.invalidate(ideasProvider) : null,
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _adding = true);
    final messenger = ScaffoldMessenger.of(context);
    final files = List<PickedIdeaFile>.from(_pending);
    try {
      final repo = ref.read(ideasRepositoryProvider);
      final id = await repo.add(text);
      // Les pièces jointes ne peuvent partir qu'une fois l'idée créée : si
      // l'une échoue, l'idée reste (le texte est le principal) et on le dit.
      final failed = <String>[];
      for (final f in files) {
        if (id <= 0) {
          failed.add(f.name);
          continue;
        }
        try {
          await repo.addFile(id, f.path, f.name);
        } catch (_) {
          failed.add(f.name);
        }
      }
      _controller.clear();
      if (mounted) setState(_pending.clear);
      ref.invalidate(ideasProvider);
      if (failed.isNotEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text('Idée ajoutée, mais ${failed.length} fichier(s) '
              'non envoyé(s) : ${failed.join(', ')}'),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Demande à Maxime d'où vient le fichier, puis le/les fait choisir.
  Future<List<PickedIdeaFile>> _pickFiles() async {
    final injected = widget.filePicker;
    if (injected != null) return injected();
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Images'),
              subtitle: const Text('Captures d\'écran, photos…'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Fichier'),
              subtitle: const Text('N\'importe quel fichier (max 10 Mo)'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return [];
    try {
      if (source == 'image') {
        final picked = await ImagePicker().pickMultiImage();
        return picked.map((x) => PickedIdeaFile(x.path, x.name)).toList();
      }
      // La sélection multiple est le défaut depuis file_picker 12.
      final result = await FilePicker.pickFiles();
      return (result?.files ?? [])
          .where((f) => f.path != null)
          .map((f) => PickedIdeaFile(f.path!, f.name))
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Choix impossible : $e')));
      }
      return [];
    }
  }

  Future<void> _attachToNew() async {
    final files = await _pickFiles();
    if (files.isEmpty || !mounted) return;
    setState(() => _pending.addAll(files));
  }

  Future<void> _edit(Idea idea) async {
    final controller = TextEditingController(text: idea.text);
    final messenger = ScaffoldMessenger.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier l\'idée'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(hintText: 'Ton idée…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || text == idea.text) return;
    try {
      await ref.read(ideasRepositoryProvider).update(idea.id, text);
      ref.invalidate(ideasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  Future<void> _confier(WidgetRef ref, Idea idea) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confier à Claude ?'),
        content: Text(
          'Claude réalisera cette idée sur le serveur puis publiera une '
          'nouvelle version. Tu la verras cochée ici une fois faite.\n\n'
          '« ${idea.text} »',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confier'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(ideasRepositoryProvider).request(idea.id);
      ref.invalidate(ideasProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Idée confiée à Claude 🤖')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  /// Feuille des pièces jointes d'une idée existante : aperçu, ajout, retrait.
  Future<void> _showAttachments(Idea idea) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AttachmentsSheet(
        idea: idea,
        pickFiles: _pickFiles,
      ),
    );
    ref.invalidate(ideasProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ideas = ref.watch(ideasProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mes idées')),
      body: Column(
        children: [
          // Ajout rapide.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'Une nouvelle idée…',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Joindre un fichier',
                      icon: const Icon(Icons.attach_file),
                      onPressed: _adding ? null : _attachToNew,
                    ),
                    _adding
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton.filled(
                            icon: const Icon(Icons.add),
                            onPressed: _add,
                          ),
                  ],
                ),
                if (_pending.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final f in _pending)
                          Chip(
                            avatar: f.isImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.file(
                                      File(f.path),
                                      width: 24,
                                      height: 24,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.image, size: 18),
                                    ),
                                  )
                                : const Icon(Icons.insert_drive_file_outlined,
                                    size: 18),
                            label: Text(
                              f.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onDeleted: () => setState(() => _pending.remove(f)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ideas.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur : $e')),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Aucune idée pour l\'instant.\n'
                        'Note tes idées ici; dis à Claude « va voir mes '
                        'idées » depuis un ordinateur.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(ideasProvider.future),
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom + 16,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final idea = list[i];
                      return Dismissible(
                        key: ValueKey(idea.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: scheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: Icon(Icons.delete, color: scheme.onErrorContainer),
                        ),
                        onDismissed: (_) async {
                          await ref
                              .read(ideasRepositoryProvider)
                              .delete(idea.id);
                          ref.invalidate(ideasProvider);
                        },
                        child: CheckboxListTile(
                          value: idea.done,
                          onChanged: (v) async {
                            await ref
                                .read(ideasRepositoryProvider)
                                .setDone(idea.id, v ?? false);
                            ref.invalidate(ideasProvider);
                          },
                          title: Text(
                            idea.text,
                            style: TextStyle(
                              decoration: idea.done
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: idea.done ? scheme.onSurfaceVariant : null,
                            ),
                          ),
                          subtitle: _IdeaSubtitle(
                            idea: idea,
                            onAttachments: () => _showAttachments(idea),
                          ),
                          secondary: (idea.done || idea.pending)
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Modifier',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _edit(idea),
                                    ),
                                    IconButton(
                                      tooltip: 'Confier à Claude',
                                      icon: const Icon(Icons.smart_toy_outlined),
                                      onPressed: () => _confier(ref, idea),
                                    ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Sous-titre d'une idée : état d'avancement + accès aux pièces jointes.
class _IdeaSubtitle extends StatelessWidget {
  const _IdeaSubtitle({required this.idea, required this.onAttachments});

  final Idea idea;
  final VoidCallback onAttachments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = idea.attachments.length;

    final status = idea.pending
        ? Row(
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                idea.status == 'in_progress'
                    ? 'Claude travaille dessus…'
                    : 'Confié à Claude — en attente',
                style: TextStyle(color: scheme.primary),
              ),
            ],
          )
        : idea.needsReview
            ? Text('À revoir (ambiguë ou risquée)',
                style: TextStyle(color: scheme.error))
            : null;

    // Une idée faite garde ses pièces jointes visibles, mais on ne propose
    // plus d'en ajouter : le travail est derrière.
    final attachments = InkWell(
      onTap: onAttachments,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                count == 0
                    ? 'Joindre un fichier'
                    : count == 1
                        ? '1 pièce jointe'
                        : '$count pièces jointes',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );

    if (idea.done && count == 0) return status ?? const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?status,
        attachments,
      ],
    );
  }
}

/// Feuille « Pièces jointes » d'une idée : aperçus, ajout, suppression.
class _AttachmentsSheet extends ConsumerStatefulWidget {
  const _AttachmentsSheet({required this.idea, required this.pickFiles});

  final Idea idea;
  final Future<List<PickedIdeaFile>> Function() pickFiles;

  @override
  ConsumerState<_AttachmentsSheet> createState() => _AttachmentsSheetState();
}

class _AttachmentsSheetState extends ConsumerState<_AttachmentsSheet> {
  late final List<IdeaAttachment> _files = List.of(widget.idea.attachments);
  bool _busy = false;

  Future<void> _add() async {
    final picked = await widget.pickFiles();
    if (picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(ideasRepositoryProvider);
    for (final f in picked) {
      try {
        final added = await repo.addFile(widget.idea.id, f.path, f.name);
        if (mounted) setState(() => _files.add(added));
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('« ${f.name} » non envoyé : $e')),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(IdeaAttachment file) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ideasRepositoryProvider).deleteFile(file.id);
      if (mounted) setState(() => _files.remove(file));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  /// Ouvre le fichier hors de l'app (visionneuse système / navigateur).
  Future<void> _open(IdeaAttachment file) async {
    final token = ref.read(authProvider).token;
    final url = ref.read(ideasRepositoryProvider).fileUrl(file, token: token);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Aucune application pour ce fichier')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headers = ref.watch(ideaFileHeadersProvider);
    final repo = ref.watch(ideasRepositoryProvider);
    final editable = !widget.idea.done;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pièces jointes',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Captures, maquettes, logs — Claude les lit avant de coder.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (_files.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Aucun fichier joint.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _files.length,
                  itemBuilder: (context, i) {
                    final f = _files[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: f.isImage
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: repo.fileUrl(f),
                                  httpHeaders: headers,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                              )
                            : Icon(Icons.insert_drive_file_outlined,
                                color: scheme.onSurfaceVariant),
                      ),
                      title: Text(f.name, overflow: TextOverflow.ellipsis),
                      subtitle: f.prettySize.isEmpty ? null : Text(f.prettySize),
                      onTap: () => _open(f),
                      trailing: editable
                          ? IconButton(
                              tooltip: 'Retirer',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _remove(f),
                            )
                          : null,
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            if (editable)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _add,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file),
                  label: const Text('Joindre'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../api/radio_repository.dart';
import '../state/radio.dart';
import '../widgets/artwork.dart';
import '../widgets/glass_kit.dart';

/// Ajout / édition d'une web radio personnalisée : nom, URL du flux, pays,
/// genres, et icône (coller une URL, ou choisir un fichier local).
class RadioEditScreen extends ConsumerStatefulWidget {
  const RadioEditScreen({super.key, this.station});

  /// null → ajout ; sinon édition (doit être une station personnalisée).
  final RadioStation? station;

  @override
  ConsumerState<RadioEditScreen> createState() => _RadioEditScreenState();
}

class _RadioEditScreenState extends ConsumerState<RadioEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _country;
  late final TextEditingController _genres;
  late final TextEditingController _logo;
  bool _busy = false;
  bool _uploading = false;

  bool get _isEdit => widget.station != null;

  @override
  void initState() {
    super.initState();
    final s = widget.station;
    _name = TextEditingController(text: s?.name ?? '');
    _url = TextEditingController(text: s?.streamUrl ?? '');
    _country = TextEditingController(text: s?.country ?? '');
    _genres = TextEditingController(text: s?.genres.join(', ') ?? '');
    _logo = TextEditingController(text: s?.logo ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _url, _country, _genres, _logo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ref
          .read(radioRepositoryProvider)
          .uploadLogo(filePath: picked.path);
      if (mounted) setState(() => _logo.text = url);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Échec de l'envoi de l'image : $e")),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  List<String> get _genreList => _genres.text
      .split(',')
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(radioRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.update(
          stationId: widget.station!.id,
          name: _name.text.trim(),
          url: _url.text.trim(),
          country: _country.text.trim(),
          genres: _genreList,
          logo: _logo.text.trim(),
        );
      } else {
        await repo.add(
          name: _name.text.trim(),
          url: _url.text.trim(),
          country: _country.text.trim(),
          genres: _genreList,
          logo: _logo.text.trim(),
        );
      }
      ref.invalidate(radioStationsProvider);
      if (mounted) context.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Échec : $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Modifier la radio' : 'Nouvelle radio'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.paddingOf(context).bottom + 100,
          ),
          children: [
            // Aperçu + choix de l'icône.
            Center(
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _uploading
                        ? const SizedBox(
                            width: 96,
                            height: 96,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Artwork(
                            url: _logo.text.trim().isEmpty
                                ? null
                                : _logo.text.trim(),
                            size: 96,
                            borderRadius: 20,
                            icon: Icons.radio,
                          ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickFile,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choisir un fichier'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _field(_name, 'Nom *', required: true),
            _field(_url, 'URL du flux *',
                required: true, keyboard: TextInputType.url, url: true),
            _field(_logo, "URL de l'icône (ou collez un lien)",
                keyboard: TextInputType.url,
                onChanged: (_) => setState(() {})),
            _field(_country, 'Pays'),
            _field(_genres, 'Genres / catégories (séparés par des virgules)'),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          child: AccentPlayButton(
            icon: Icons.check,
            label: _busy ? 'Enregistrement…' : 'Enregistrer',
            onPressed: _busy ? null : _save,
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    bool url = false,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          final t = (v ?? '').trim();
          if (required && t.isEmpty) return 'Requis';
          if (url && t.isNotEmpty && Uri.tryParse(t)?.hasScheme != true) {
            return 'URL invalide (commence par http…)';
          }
          return null;
        },
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/song.dart';
import '../state/auth.dart';
import '../state/player.dart';
import '../widgets/artwork.dart';

/// Maisons amies (3.82.0, serveur 1.8.0, GulliOS 1.49) : écouter la musique
/// que des personnes d'une AUTRE maison GulliOS partagent. Rien n'est copié :
/// la liste et les titres se lisent chez elle, avec le billet que notre
/// serveur nous remet (signé par gullify.app, valable quelques heures). Écoute
/// seulement : ni favoris, ni listes, ni téléchargement.

class MaisonAmie {
  const MaisonAmie(this.nom, this.adresse, this.billet);
  final String nom;
  final String adresse;
  final String billet;

  /// Le client de SA maison : sans notre jeton (il ne doit jamais partir chez elle).
  ApiClient get client => ApiClient(serverUrl: 'https://$adresse');

  String abs(String? relative) => relative == null ? '' : 'https://$adresse/$relative';

  Future<dynamic> lire(String action, [Map<String, dynamic> plus = const {}]) =>
      client.get('amies.php', query: {'action': action, 'billet': billet, ...plus});

  /// Un titre prêt pour le lecteur : lu chez elle, id négatif (inconnu chez nous).
  Song titre(Map<String, dynamic> t) => Song(
        id: -(1000000000 + (t['id'] as int)),
        title: t['titre'] as String? ?? '',
        filePath: '',
        trackNumber: t['piste'] as int?,
        duration: t['duree'] as int? ?? 0,
        albumName: t['album'] as String?,
        artistName: t['artiste'] as String?,
        artworkUrl: abs(t['artworkUrl'] as String?),
        streamUrl: '${abs(t['flux'] as String)}&billet=${Uri.encodeQueryComponent(billet)}',
      );
}

/// Nos maisons amies, telles que notre serveur les connaît.
final maisonsAmiesProvider = FutureProvider.autoDispose<List<MaisonAmie>>((ref) async {
  final d = await ref.watch(apiClientProvider).get('amies.php', query: {'action': 'maisons'}) as Map<String, dynamic>;
  return [
    for (final m in (d['maisons'] as List? ?? const []))
      MaisonAmie(m['nom'] as String, m['adresse'] as String, m['billet'] as String),
  ];
});

/// Les personnes qui partagent, dans chaque maison amie (null : hors ligne).
final personnesAmiesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>?, MaisonAmie>((ref, m) async {
  try {
    final l = await m.lire('personnes').timeout(const Duration(seconds: 8)) as List;
    return l.cast<Map<String, dynamic>>();
  } catch (_) {
    return null;
  }
});

class MaisonsAmiesScreen extends ConsumerWidget {
  const MaisonsAmiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maisons = ref.watch(maisonsAmiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Autres maisons')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(maisonsAmiesProvider.future),
        child: maisons.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Vide('Ta maison ne répond pas ($e).'),
          data: (liste) => liste.isEmpty
              ? const _Vide('Aucune maison amie. Invite une maison dans les Réglages de ta '
                  'maison GulliOS (Maisons amies).')
              : ListView(
                  children: [
                    for (final m in liste) ...[
                      _Titre('Chez ${m.nom}'),
                      _Personnes(maison: m),
                    ],
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Écoute seulement : pas de téléchargement ni de copie dans ta bibliothèque.',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98))),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Personnes extends ConsumerWidget {
  const _Personnes({required this.maison});
  final MaisonAmie maison;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personnes = ref.watch(personnesAmiesProvider(maison));
    return personnes.when(
      loading: () => const Padding(padding: EdgeInsets.all(18), child: LinearProgressIndicator()),
      error: (_, _) => const _Note('Hors ligne : sa musique reviendra quand la maison sera allumée.'),
      data: (l) => l == null
          ? const _Note('Hors ligne : sa musique reviendra quand la maison sera allumée.')
          : l.isEmpty
              ? const _Note('Personne ne partage sa musique pour l\'instant.')
              : Column(children: [
                  for (final p in l)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(p['nom'] as String? ?? ''),
                      subtitle: Text('${p['titres']} titres · ${p['artistes']} artistes'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PersonneAmieScreen(maison: maison, personne: p))),
                    ),
                ]),
    );
  }
}

/// La musique d'une personne : ses artistes, et une recherche.
class PersonneAmieScreen extends StatefulWidget {
  const PersonneAmieScreen({super.key, required this.maison, required this.personne});
  final MaisonAmie maison;
  final Map<String, dynamic> personne;

  @override
  State<PersonneAmieScreen> createState() => PersonneAmieScreenState();
}

class PersonneAmieScreenState extends State<PersonneAmieScreen> {
  final List<Map<String, dynamic>> _artistes = [];
  Map<String, dynamic>? _resultats;
  int _total = 0;
  bool _charge = false;
  String? _erreur;
  Timer? _attente;

  int get _id => widget.personne['id'] as int;

  @override
  void initState() {
    super.initState();
    _suite();
  }

  @override
  void dispose() {
    _attente?.cancel();
    super.dispose();
  }

  Future<void> _suite() async {
    if (_charge) return;
    setState(() => _charge = true);
    try {
      final d = await widget.maison.lire('artistes', {'personne': _id, 'offset': _artistes.length, 'limit': 200})
          as Map<String, dynamic>;
      setState(() {
        _artistes.addAll((d['artistes'] as List).cast<Map<String, dynamic>>());
        _total = d['total'] as int;
      });
    } catch (e) {
      setState(() => _erreur = '$e');
    } finally {
      if (mounted) setState(() => _charge = false);
    }
  }

  void _chercher(String q) {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 350), () async {
      if (q.trim().length < 2) return setState(() => _resultats = null);
      try {
        final r = await widget.maison.lire('recherche', {'personne': _id, 'q': q.trim()}) as Map<String, dynamic>;
        if (mounted) setState(() => _resultats = r);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.maison;
    final r = _resultats;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.personne['nom']} · ${m.nom}')),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (r == null && n.metrics.extentAfter < 600 && _artistes.length < _total) _suite();
          return false;
        },
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: _chercher,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Chercher dans la musique de ${widget.personne['nom']}',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            if (_erreur != null) _Note('Sa maison ne répond pas ($_erreur).'),
            if (r != null) ...[
              if ((r['titres'] as List).isNotEmpty) const _Titre('Titres'),
              _Titres(maison: m, titres: (r['titres'] as List).cast<Map<String, dynamic>>()),
              if ((r['albums'] as List).isNotEmpty) const _Titre('Albums'),
              for (final al in (r['albums'] as List).cast<Map<String, dynamic>>())
                _LigneAlbum(maison: m, personne: _id, album: al, sousTitre: al['artiste'] as String?),
              if ((r['artistes'] as List).isNotEmpty) const _Titre('Artistes'),
              for (final a in (r['artistes'] as List).cast<Map<String, dynamic>>())
                _LigneArtiste(maison: m, personne: _id, artiste: a),
            ] else ...[
              for (final a in _artistes) _LigneArtiste(maison: m, personne: _id, artiste: a),
              if (_charge) const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArtisteScreen extends StatelessWidget {
  const _ArtisteScreen({required this.maison, required this.personne, required this.artiste});
  final MaisonAmie maison;
  final int personne;
  final Map<String, dynamic> artiste;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(artiste['nom'] as String? ?? '')),
      body: FutureBuilder<dynamic>(
        future: maison.lire('artiste', {'personne': personne, 'id': artiste['id']}),
        builder: (context, s) {
          if (s.hasError) return _Vide('Sa maison ne répond pas (${s.error}).');
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final albums = ((s.data as Map<String, dynamic>)['albums'] as List).cast<Map<String, dynamic>>();
          return ListView(children: [
            for (final al in albums)
              _LigneAlbum(maison: maison, personne: personne, album: al,
                  sousTitre: [al['annee'], '${al['titres']} titres'].whereType<Object>().join(' · ')),
          ]);
        },
      ),
    );
  }
}

class _AlbumScreen extends StatelessWidget {
  const _AlbumScreen({required this.maison, required this.personne, required this.album});
  final MaisonAmie maison;
  final int personne;
  final Map<String, dynamic> album;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(album['nom'] as String? ?? '')),
      body: FutureBuilder<dynamic>(
        future: maison.lire('album', {'personne': personne, 'id': album['id']}),
        builder: (context, s) {
          if (s.hasError) return _Vide('Sa maison ne répond pas (${s.error}).');
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final d = s.data as Map<String, dynamic>;
          final al = d['album'] as Map<String, dynamic>;
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Artwork(url: maison.abs(al['artworkUrl'] as String?), size: 110),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(al['nom'] as String? ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    Text([(al['artiste'] as Map)['nom'], al['annee']].whereType<Object>().join(' · ')),
                    Text('chez ${maison.nom}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98))),
                  ]),
                ),
              ]),
            ),
            _Titres(maison: maison, titres: (d['titres'] as List).cast<Map<String, dynamic>>(), pochettes: false),
          ]);
        },
      ),
    );
  }
}

/// Des titres : un toucher joue la liste à partir de celui-ci, chez la maison amie.
class _Titres extends ConsumerWidget {
  const _Titres({required this.maison, required this.titres, this.pochettes = true});
  final MaisonAmie maison;
  final List<Map<String, dynamic>> titres;
  final bool pochettes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(children: [
      for (var i = 0; i < titres.length; i++)
        ListTile(
          leading: pochettes
              ? Artwork(url: maison.abs(titres[i]['artworkUrl'] as String?), size: 44, borderRadius: 6)
              : SizedBox(width: 28, child: Text('${titres[i]['piste'] ?? ''}', textAlign: TextAlign.center)),
          title: Text(titres[i]['titre'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(titres[i]['artiste'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(_duree(titres[i]['duree'] as int? ?? 0)),
          onTap: () => ref.read(playerActionsProvider).playSongs([for (final t in titres) maison.titre(t)], startIndex: i),
        ),
    ]);
  }

  static String _duree(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _LigneArtiste extends StatelessWidget {
  const _LigneArtiste({required this.maison, required this.personne, required this.artiste});
  final MaisonAmie maison;
  final int personne;
  final Map<String, dynamic> artiste;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Artwork(url: artiste['imageUrl'] == null ? null : maison.abs(artiste['imageUrl'] as String),
            size: 48, borderRadius: 24, icon: Icons.person),
        title: Text(artiste['nom'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${artiste['albums']} album${(artiste['albums'] as int? ?? 0) > 1 ? 's' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _ArtisteScreen(maison: maison, personne: personne, artiste: artiste))),
      );
}

class _LigneAlbum extends StatelessWidget {
  const _LigneAlbum({required this.maison, required this.personne, required this.album, this.sousTitre});
  final MaisonAmie maison;
  final int personne;
  final Map<String, dynamic> album;
  final String? sousTitre;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Artwork(url: maison.abs(album['artworkUrl'] as String?), size: 48, borderRadius: 6),
        title: Text(album['nom'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: sousTitre == null ? null : Text(sousTitre!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _AlbumScreen(maison: maison, personne: personne, album: album))),
      );
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
        child: Text(texte, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
        child: Text(texte, style: const TextStyle(fontSize: 13.5, color: Color(0xFF8A8F98))),
      );
}

class _Vide extends StatelessWidget {
  const _Vide(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => ListView(children: [
        const SizedBox(height: 120),
        Padding(padding: const EdgeInsets.all(24), child: Text(texte, textAlign: TextAlign.center)),
      ]);
}

/// Paramètres › Bibliothèque : partager SA musique avec les maisons amies.
/// Invisible quand le serveur ne connaît pas de maisons amies (gullify.app,
/// maison sans GulliOS 1.49, serveur plus ancien).
class PartageAmiesTile extends ConsumerStatefulWidget {
  const PartageAmiesTile({super.key});

  @override
  ConsumerState<PartageAmiesTile> createState() => _PartageAmiesTileState();
}

class _PartageAmiesTileState extends ConsumerState<PartageAmiesTile> {
  bool? _partage;
  bool _actif = false;

  @override
  void initState() {
    super.initState();
    ref.read(apiClientProvider).get('amies.php', query: {'action': 'moi'}).then((d) {
      if (mounted) {
        setState(() {
          _actif = d['actif'] == true;
          _partage = d['partage'] == true;
        });
      }
    }).catchError((_) {});
  }

  Future<void> _changer(bool v) async {
    setState(() => _partage = v);
    try {
      final d = await ref.read(apiClientProvider).post('amies.php', query: {'action': 'moi'}, body: {'partage': v});
      if (mounted) setState(() => _partage = d['partage'] == true);
    } catch (_) {
      if (mounted) setState(() => _partage = !v);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_actif) return const SizedBox.shrink();
    return Column(children: [
      SwitchListTile(
        secondary: const Icon(Icons.share_outlined),
        title: const Text('Partager ma musique avec les maisons amies'),
        subtitle: const Text('Elles peuvent l\'écouter (sans la copier) quand ta maison est allumée'),
        value: _partage ?? false,
        onChanged: _partage == null ? null : _changer,
      ),
    ]);
  }
}

/// Toutes les personnes qui partagent, dans toutes les maisons amies en ligne
/// (pour l'onglet Recherche). Vide sans maison amie : rien ne s'affiche.
final personnesDesAmiesProvider =
    FutureProvider.autoDispose<List<(MaisonAmie, Map<String, dynamic>)>>((ref) async {
  final maisons = await ref.watch(maisonsAmiesProvider.future);
  final listes = await Future.wait([for (final m in maisons) ref.watch(personnesAmiesProvider(m).future)]);
  return [
    for (var i = 0; i < maisons.length; i++)
      for (final p in listes[i] ?? const <Map<String, dynamic>>[]) (maisons[i], p),
  ];
});

/// Onglet Recherche (3.83.0) : les personnes des maisons amies, comme les
/// utilisateurs dans YouTube Music. Sans [filtre] (champ vide) : toutes, sous
/// « Autres maisons » ; avec : celles dont le nom contient le texte cherché.
class AmiesRecherche extends ConsumerWidget {
  const AmiesRecherche({super.key, this.filtre});
  final String? filtre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tout = ref.watch(personnesDesAmiesProvider).value ?? const [];
    final f = filtre?.trim().toLowerCase();
    final liste = f == null || f.isEmpty
        ? tout
        : [for (final x in tout) if ((x.$2['nom'] as String? ?? '').toLowerCase().contains(f)) x];
    if (liste.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
        child: Text(filtre == null ? 'Autres maisons' : 'Personnes',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      ),
      if (filtre == null)
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Text('La musique que partagent les maisons amies',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98))),
        ),
      for (final (m, p) in liste)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(p['nom'] as String? ?? ''),
          subtitle: Text('chez ${m.nom} · ${p['titres']} titres'),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFFB6BAC1)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PersonneAmieScreen(maison: m, personne: p))),
        ),
    ]);
  }
}

import 'dart:math';

import '../models/song.dart';
import 'api_client.dart';
import 'library_repository.dart';

/// Un titre recommandé : le titre, d'où il vient (`mix:2`, `auto:voisins`…,
/// renvoyé au serveur avec l'écoute pour qu'il apprenne) et pourquoi.
class RecoSong {
  const RecoSong({required this.song, this.origin, this.raison});

  final Song song;
  final String? origin;
  final String? raison;
}

/// Un artiste hors de la bibliothèque (rayon « À découvrir ailleurs »).
class RecoArtiste {
  const RecoArtiste({
    required this.nom,
    this.image,
    this.parce = const [],
    this.tags = const [],
    this.phrase,
  });

  factory RecoArtiste.fromJson(Map<String, dynamic> j) => RecoArtiste(
    nom: j['nom'] as String? ?? '',
    image: j['image'] as String?,
    parce: [for (final p in j['parce'] as List? ?? const []) '$p'],
    tags: [for (final t in j['tags'] as List? ?? const []) '$t'],
    phrase: j['phrase'] as String?,
  );

  final String nom;
  final String? image;

  /// Les artistes aimés qui l'amènent.
  final List<String> parce;
  final List<String> tags;

  /// Une phrase écrite par le modèle de langue, s'il y en a un.
  final String? phrase;

  String get pourquoi {
    if (phrase != null && phrase!.isNotEmpty) return phrase!;
    if (parce.isEmpty) return 'Proche de tes goûts';
    return parce.length == 1
        ? 'Parce que tu aimes ${parce.first}'
        : 'Parce que tu aimes ${parce[0]} et ${parce[1]}';
  }
}

/// Un rayon de l'accueil (mix, découvertes, en boucle…).
class Rayon {
  const Rayon({
    required this.id,
    required this.type,
    required this.titre,
    this.sousTitre,
    this.nombre = 0,
    this.apercu = const [],
    this.artistes = const [],
    this.numero,
  });

  final int id;

  /// mix, decouvertes, boucle, oubliees, moment, ailleurs
  final String type;
  final String titre;
  final String? sousTitre;
  final int nombre;

  /// Jusqu'à quatre pochettes pour la vignette.
  final List<String> apercu;
  final List<RecoArtiste> artistes;
  final int? numero;
}

class RayonDetail {
  const RayonDetail({required this.rayon, required this.titres});

  final Rayon rayon;
  final List<RecoSong> titres;
}

class PourToiAccueil {
  const PourToiAccueil({required this.rayons, this.analyseLe});

  final List<Rayon> rayons;
  final String? analyseLe;
}

/// « Tes goûts » : ce que la maison a compris, en clair.
class GoutsProfil {
  const GoutsProfil(this.json);

  final Map<String, dynamic> json;

  String get portrait => json['portrait'] as String? ?? '';
  String get profil => json['profil'] as String? ?? '';
  double get aventure => (json['aventure'] as num?)?.toDouble() ?? 0.35;

  List<({String nom, double part})> get etiquettes => [
    for (final e in json['etiquettes'] as List? ?? const [])
      (
        nom: (e as Map)['nom'] as String? ?? '',
        part: (e['part'] as num?)?.toDouble() ?? 0,
      ),
  ];

  List<({int id, String nom, String? imageUrl, int ecoutes})> get artistes => [
    for (final a in json['artistes'] as List? ?? const [])
      (
        id: ((a as Map)['id'] as num).toInt(),
        nom: a['nom'] as String? ?? '',
        imageUrl: a['imageUrl'] as String?,
        ecoutes: (a['ecoutes'] as num?)?.toInt() ?? 0,
      ),
  ];

  Map<String, dynamic> get habitudes =>
      (json['habitudes'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<int> get heures => [
    for (final h in habitudes['heures'] as List? ?? const [])
      (h as num).toInt(),
  ];

  List<({String nom, int ecoutes, double taux})> get reussite => [
    for (final r in json['reussite'] as List? ?? const [])
      (
        nom: (r as Map)['nom'] as String? ?? '',
        ecoutes: (r['ecoutes'] as num?)?.toInt() ?? 0,
        taux: (r['taux'] as num?)?.toDouble() ?? 0,
      ),
  ];

  List<({String nom, int essais, double taux})> get appris => [
    for (final r in json['appris'] as List? ?? const [])
      (
        nom: (r as Map)['nom'] as String? ?? '',
        essais: (r['essais'] as num?)?.toInt() ?? 0,
        taux: (r['taux'] as num?)?.toDouble() ?? 0,
      ),
  ];

  List<({String type, int id, String nom, String? artiste})> get rejets => [
    for (final r in json['rejets'] as List? ?? const [])
      (
        type: (r as Map)['type'] as String? ?? 'song',
        id: (r['id'] as num).toInt(),
        nom: r['nom'] as String? ?? '',
        artiste: r['artiste'] as String?,
      ),
  ];

  Map<String, dynamic> get sources =>
      (json['sources'] as Map?)?.cast<String, dynamic>() ?? const {};
}

/// Pour toi (serveur 1.11.0, `api/v2/pour-toi.php`) : les rayons calculés la
/// nuit, la suite d'un morceau (lecture automatique, radio d'un titre), le
/// portrait et ses réglages.
class PourToiRepository {
  PourToiRepository(this._client, this._library);

  final ApiClient _client;
  final LibraryRepository _library;

  /// Le fuseau du téléphone, en minutes : le serveur vit en UTC, et le « mix
  /// du soir » doit tomber le soir d'ici.
  int get _decalage => DateTime.now().timeZoneOffset.inMinutes;

  RecoSong _reco(Map<String, dynamic> j) => RecoSong(
    song: _library.songFromJson(j),
    origin: j['origin'] as String?,
    raison: j['raison'] as String?,
  );

  List<RecoSong> _recos(dynamic list) => [
    for (final j in list as List? ?? const [])
      _reco((j as Map).cast<String, dynamic>()),
  ];

  Rayon _rayon(Map<String, dynamic> j) => Rayon(
    id: (j['id'] as num).toInt(),
    type: j['type'] as String? ?? '',
    titre: j['titre'] as String? ?? '',
    sousTitre: j['sousTitre'] as String?,
    nombre: (j['nombre'] as num?)?.toInt() ?? 0,
    apercu: [
      for (final u in j['apercu'] as List? ?? const [])
        if (_library.absoluteUrl('$u') case final String url) url,
    ],
    artistes: [
      for (final a in j['artistes'] as List? ?? const [])
        if (a is Map) RecoArtiste.fromJson(a.cast<String, dynamic>()),
    ],
    numero: (j['numero'] as num?)?.toInt(),
  );

  Future<PourToiAccueil> accueil() async {
    final data =
        await _client.get(
              'pour-toi.php',
              query: {'action': 'accueil', 'decalage': _decalage},
            )
            as Map<String, dynamic>;
    return PourToiAccueil(
      rayons: [
        for (final r in data['rayons'] as List? ?? const [])
          _rayon((r as Map).cast<String, dynamic>()),
      ],
      analyseLe: data['analyseLe'] as String?,
    );
  }

  Future<RayonDetail> rayon(int id) async {
    final data =
        await _client.get('pour-toi.php', query: {'action': 'rayon', 'id': id})
            as Map<String, dynamic>;
    return RayonDetail(rayon: _rayon(data), titres: _recos(data['titres']));
  }

  /// La suite de ce qui joue : [graines] = derniers titres (le plus récent en
  /// dernier), [exclus] = ce qui est déjà dans la file.
  Future<List<RecoSong>> suite({
    required List<int> graines,
    List<int> exclus = const [],
    int n = 10,
    bool radio = false,
  }) async {
    final data =
        await _client.get(
              'pour-toi.php',
              query: {
                'action': 'suite',
                'graines': graines.join(','),
                'exclus': exclus.take(400).join(','),
                'n': n,
                'famille': radio ? 'radio' : 'auto',
              },
            )
            as Map<String, dynamic>;
    return _recos(data['titres']);
  }

  /// La radio d'un titre : lui, puis sa suite.
  Future<List<RecoSong>> radio(int songId, {int n = 25}) async {
    final data =
        await _client.get(
              'pour-toi.php',
              query: {'action': 'radio', 'titre': songId, 'n': n},
            )
            as Map<String, dynamic>;
    return _recos(data['titres']);
  }

  Future<GoutsProfil> profil() async {
    final data =
        await _client.get(
              'pour-toi.php',
              query: {'action': 'profil', 'decalage': _decalage},
            )
            as Map<String, dynamic>;
    return GoutsProfil(data);
  }

  Future<void> setAventure(double valeur) => _client.post(
    'pour-toi.php',
    query: {'action': 'aventure'},
    body: {'valeur': valeur},
  );

  /// « Pas pour moi » : [type] = song ou artist.
  Future<void> rejeter(String type, int id) => _client.post(
    'pour-toi.php',
    query: {'action': 'rejeter'},
    body: {'type': type, 'id': id},
  );

  Future<void> retablir(String type, int id) => _client.post(
    'pour-toi.php',
    query: {'action': 'retablir'},
    body: {'type': type, 'id': id},
  );

  Future<void> analyser() =>
      _client.post('pour-toi.php', query: {'action': 'analyser'});
}

/// Mélange une liste recommandée pour la lancer : les listes « Pour toi »
/// partent TOUJOURS en aléatoire (demande de Maxime) — sur un court trajet,
/// partir dans l'ordre, c'est réentendre chaque fois les mêmes premiers
/// titres. Un nouveau tirage à chaque lancement, sans deux titres du même
/// artiste à la suite quand on peut l'éviter.
///
/// [premier] : le titre touché dans la liste, qui joue d'abord ; le reste
/// est mélangé derrière lui.
List<RecoSong> melangerPourLancer(
  List<RecoSong> titres, {
  RecoSong? premier,
  Random? hasard,
}) {
  final reste = [...titres]..shuffle(hasard ?? Random());
  final out = <RecoSong>[];
  if (premier != null) {
    reste.remove(premier);
    out.add(premier);
  }
  String? artiste(RecoSong r) => r.song.artistName?.toLowerCase();
  final compte = <String?, int>{};
  for (final r in reste) {
    compte[artiste(r)] = (compte[artiste(r)] ?? 0) + 1;
  }
  while (reste.isNotEmpty) {
    final dernier = out.isEmpty ? null : artiste(out.last);
    // Un artiste qui tient plus de la moitié de ce qui reste doit passer
    // maintenant, sinon la fin de liste n'aurait plus que lui.
    final presse = compte.entries
        .where((e) => e.key != dernier && e.value * 2 > reste.length)
        .map((e) => e.key)
        .firstOrNull;
    var i = presse != null
        ? reste.indexWhere((r) => artiste(r) == presse)
        : reste.indexWhere((r) => out.isEmpty || artiste(r) != dernier);
    if (i < 0) i = 0;
    final r = reste.removeAt(i);
    compte[artiste(r)] = compte[artiste(r)]! - 1;
    out.add(r);
  }
  return out;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../audio/audio_handler.dart';
import '../state/auth.dart';
import '../state/player.dart';

/// « Écouter sur… » (app 3.99.0, serveur 1.23.0, GulliOS 1.139).
///
/// Le téléphone fait jouer sa file par un autre appareil du Wi-Fi où il se
/// trouve — chez soi ou en visite : une télé où GulliFY est ouvert, un poste ou
/// un serveur GulliOS. L'appareil choisi lit lui-même la musique, depuis le
/// serveur GulliFY DU TÉLÉPHONE, avec un billet d'écoute par titre (un
/// fichier, 12 h : `api/v2/ecoute.php`) ; le jeton de session ne quitte jamais
/// le téléphone. Le téléphone devient la télécommande.
///
/// Protocole v1, JSON sur HTTP, port 47830, annoncé en mDNS
/// `_gullify-ecoute._tcp` (le même que `gullios.ecoute` de GulliOS) :
///   GET  /etat     → {v, nom, genre, de, file, index, position, duree, pause, volume, actif}
///   POST /jouer    {de, file: [{titre, artiste, album, pochette, url}], index, position}
///   POST /commande {geste: pause|reprendre|suivant|precedent|aller|chercher|volume|arreter, valeur}
///
/// Décision de Maxime (2026-11-14) : tout appareil du Wi-Fi, sans accord à
/// l'écran.
const kEcoutePort = 47830;
const kEcouteType = '_gullify-ecoute._tcp';

/// Un appareil vu sur le Wi-Fi.
class Appareil {
  const Appareil({
    required this.cle,
    required this.nom,
    required this.hote,
    required this.port,
    this.genre = 'gullios',
    this.dispo = false,
  });

  /// Nom de l'annonce mDNS : stable tant que l'appareil est là.
  final String cle;
  final String nom;
  final String hote;
  final int port;

  /// `tv`, `poste`, `serveur` (ou `gullios` tant qu'on ne lui a pas parlé).
  final String genre;

  /// Il a répondu à /etat : quelqu'un y est connecté (poste) ou l'app est
  /// ouverte (télé). Sinon il s'annonce mais ne joue pas : grisé.
  final bool dispo;

  String get base => 'http://${hote.contains(':') ? '[$hote]' : hote}:$port';

  String get description => switch (genre) {
    'tv' => 'Télé · GulliFY ouvert',
    'poste' => dispo ? 'Poste GulliOS' : 'Poste GulliOS · personne de connecté',
    'serveur' => 'Serveur GulliOS',
    _ => dispo ? 'GulliOS' : 'Ne répond pas',
  };

  Appareil avec({String? nom, String? genre, bool? dispo}) => Appareil(
    cle: cle,
    nom: nom ?? this.nom,
    hote: hote,
    port: port,
    genre: genre ?? this.genre,
    dispo: dispo ?? this.dispo,
  );
}

/// Ce que l'appareil répond à /etat.
class EtatDistant {
  const EtatDistant({
    this.nom = '',
    this.genre = '',
    this.de = '',
    this.file = const [],
    this.index = -1,
    this.position = Duration.zero,
    this.duree = Duration.zero,
    this.pause = true,
    this.volume,
    this.actif = false,
  });

  factory EtatDistant.fromJson(Map<String, dynamic> j) {
    Duration s(Object? v) => Duration(
      milliseconds: ((v is num ? v : 0) * 1000).round(),
    );
    return EtatDistant(
      nom: j['nom'] as String? ?? '',
      genre: j['genre'] as String? ?? '',
      de: j['de'] as String? ?? '',
      file: [
        for (final t in (j['file'] as List? ?? const []))
          if (t is Map) Map<String, dynamic>.from(t),
      ],
      index: (j['index'] as num?)?.toInt() ?? -1,
      position: s(j['position']),
      duree: s(j['duree']),
      pause: j['pause'] as bool? ?? true,
      volume: (j['volume'] as num?)?.toDouble(),
      actif: j['actif'] as bool? ?? false,
    );
  }

  final String nom;
  final String genre;
  final String de;
  final List<Map<String, dynamic>> file;
  final int index;
  final Duration position;
  final Duration duree;
  final bool pause;

  /// 0 à 100 ; null quand l'appareil le règle lui-même (la télé : sa
  /// télécommande).
  final double? volume;
  final bool actif;

  Map<String, dynamic>? get titre =>
      actif && index >= 0 && index < file.length ? file[index] : null;
}

final _dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 6),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
  ),
);

Future<EtatDistant> _etat(Appareil a) async {
  final r = await _dio.get<dynamic>('${a.base}/etat');
  return EtatDistant.fromJson(Map<String, dynamic>.from(r.data as Map));
}

Future<EtatDistant> _poster(Appareil a, String chemin, Object corps) async {
  final r = await _dio.post<dynamic>('${a.base}$chemin', data: corps);
  return EtatDistant.fromJson(Map<String, dynamic>.from(r.data as Map));
}

// ── La découverte ────────────────────────────────────────────────────────────

/// Les appareils du Wi-Fi, tant que la liste « Écouter sur… » est ouverte.
final appareilsProvider =
    NotifierProvider.autoDispose<Appareils, List<Appareil>>(Appareils.new);

class Appareils extends Notifier<List<Appareil>> {
  nsd.Discovery? _decouverte;
  bool _fini = false;

  @override
  List<Appareil> build() {
    _fini = false;
    ref.onDispose(() {
      _fini = true;
      final d = _decouverte;
      _decouverte = null;
      if (d != null) unawaited(nsd.stopDiscovery(d).catchError((_) {}));
    });
    if (!kIsWeb) unawaited(_demarrer());
    return const [];
  }

  Future<void> _demarrer() async {
    try {
      final d = await nsd.startDiscovery(
        kEcouteType,
        ipLookupType: nsd.IpLookupType.any,
      );
      if (_fini) {
        await nsd.stopDiscovery(d);
        return;
      }
      _decouverte = d;
      d.addServiceListener((service, statut) {
        if (statut == nsd.ServiceStatus.found) {
          _trouve(service);
        } else {
          state = [for (final a in state) if (a.cle != service.name) a];
        }
      });
    } catch (e) {
      debugPrint('Écouter sur… : découverte impossible — $e');
    }
  }

  void _trouve(nsd.Service s) {
    final adresses = s.addresses ?? const <InternetAddress>[];
    final v4 = adresses.where((a) => a.type == InternetAddressType.IPv4);
    final hote = v4.isNotEmpty
        ? v4.first.address
        : adresses.isNotEmpty
        ? adresses.first.address
        : s.host;
    if (hote == null || s.port == null || s.name == null) return;
    String? txt(String k) {
      final v = s.txt?[k];
      return v == null ? null : utf8.decode(v, allowMalformed: true);
    }

    final a = Appareil(
      cle: s.name!,
      nom: s.name!,
      hote: hote,
      port: s.port!,
      genre: txt('genre') ?? 'gullios',
    );
    // Soi-même (la télé qui s'annonce, vue d'elle-même) : pas dans la liste.
    if (Recepteur.instance?.nomAnnonce == a.cle) return;
    state = [for (final x in state) if (x.cle != a.cle) x, a];
    unawaited(_sonder(a));
  }

  Future<void> _sonder(Appareil a) async {
    try {
      final e = await _etat(a);
      if (_fini) return;
      final b = a.avec(
        nom: e.nom.isNotEmpty && a.genre != 'tv' ? e.nom : a.nom,
        genre: e.genre.isNotEmpty ? e.genre : a.genre,
        dispo: true,
      );
      state = [for (final x in state) if (x.cle == a.cle) b else x];
    } catch (_) {
      // Il s'annonce mais ne répond pas : un poste où personne n'est connecté.
    }
  }
}

// ── Le téléphone, télécommande ───────────────────────────────────────────────

class Cible {
  const Cible(this.appareil, this.etat);
  final Appareil appareil;
  final EtatDistant etat;
}

/// L'appareil où joue la musique, ou null : elle joue ici.
final cibleProvider = NotifierProvider<CibleNotifier, Cible?>(
  CibleNotifier.new,
);

class CibleNotifier extends Notifier<Cible?> {
  Timer? _sonde;
  int _echecs = 0;

  @override
  Cible? build() {
    ref.onDispose(() => _sonde?.cancel());
    return null;
  }

  /// Envoie la file d'ici à [a], au titre et à la seconde où l'on en est, puis
  /// met ce téléphone en pause.
  Future<void> envoyer(Appareil a) async {
    final handler = ref.read(audioHandlerProvider);
    final client = ref.read(apiClientProvider);
    final user = ref.read(authProvider).user;
    final items = handler.queue.value;
    final lecture = handler.playbackState.value;
    if (items.isEmpty) throw StateError('Rien à envoyer : la file est vide.');
    final courant = handler.mediaItem.value;
    var index = lecture.queueIndex ?? items.indexWhere((i) => i.id == courant?.id);
    if (index < 0 || index >= items.length) index = 0;

    // Un billet pour chaque titre de la bibliothèque ; une radio ou un balado
    // public part tel quel ; un fichier du téléphone, ou une adresse qui porte
    // un jeton, ne part pas.
    final chemins = [
      for (final i in items)
        if (i.extras?['filePath'] case final String p when p.isNotEmpty) p,
    ];
    var billets = <String, String>{};
    if (chemins.isNotEmpty) {
      final r =
          await client.post('ecoute.php?action=billets', body: {'chemins': chemins})
              as Map;
      billets = Map<String, String>.from(r['billets'] as Map? ?? const {});
    }
    final serveur = client.serverUrl();
    final file = <Map<String, String>>[];
    var nouvelIndex = 0;
    for (var n = 0; n < items.length; n++) {
      final i = items[n];
      final chemin = i.extras?['filePath'] as String?;
      String? url;
      if (chemin != null && billets[chemin] != null) {
        url = '$serveur/stream.php?path=${Uri.encodeQueryComponent(chemin)}'
            '&ecoute=${Uri.encodeQueryComponent(billets[chemin]!)}';
      } else if (i.id.startsWith('http') && !i.id.contains('token=')) {
        url = i.id;
      }
      if (url == null) continue;
      if (n == index) nouvelIndex = file.length;
      final art = i.artUri;
      file.add({
        'titre': i.title,
        'artiste': i.artist ?? '',
        'album': i.album ?? '',
        if (art != null && art.scheme.startsWith('http') &&
            !art.toString().contains('token='))
          'pochette': art.toString(),
        'url': url,
      });
    }
    if (file.isEmpty) {
      throw StateError('Ces titres ne peuvent pas être joués ailleurs.');
    }
    final de = (user?.fullName?.trim().isNotEmpty ?? false)
        ? user!.fullName!.trim().split(' ').first
        : (user?.username ?? 'quelqu\'un');
    final etat = await _poster(a, '/jouer', {
      'de': de,
      'file': file,
      'index': nouvelIndex,
      'position': lecture.position.inMilliseconds / 1000,
    });
    await handler.pause();
    state = Cible(a.avec(dispo: true), etat);
    _echecs = 0;
    _sonde?.cancel();
    _sonde = Timer.periodic(const Duration(seconds: 1), (_) => _rafraichir());
  }

  Future<void> _rafraichir() async {
    final c = state;
    if (c == null) return;
    try {
      final e = await _etat(c.appareil);
      if (state?.appareil.cle != c.appareil.cle) return;
      _echecs = 0;
      // Quelqu'un d'autre a pris l'appareil, ou il s'est arrêté : on lâche.
      if (!e.actif) {
        _lacher();
        return;
      }
      state = Cible(c.appareil, e);
    } catch (_) {
      if (++_echecs >= 10) _lacher();
    }
  }

  Future<void> commande(String geste, [Object? valeur]) async {
    final c = state;
    if (c == null) return;
    try {
      final e = await _poster(c.appareil, '/commande', {
        'geste': geste,
        'valeur': ?valeur,
      });
      if (state?.appareil.cle == c.appareil.cle) state = Cible(c.appareil, e);
    } catch (e) {
      debugPrint('Écouter sur… : $geste refusé — $e');
    }
  }

  /// Revenir à « Ce téléphone » : l'appareil s'arrête, la lecture reprend ici
  /// au titre et à la seconde où il en était (si c'est un titre de notre file).
  Future<void> revenir() async {
    final c = state;
    if (c == null) return;
    _lacher();
    final handler = ref.read(audioHandlerProvider);
    try {
      await _poster(c.appareil, '/commande', {'geste': 'arreter'});
    } catch (_) {}
    final titre = c.etat.titre;
    if (titre == null) return;
    final items = handler.queue.value;
    final i = items.indexWhere(
      (m) => m.title == titre['titre'] && (m.artist ?? '') == titre['artiste'],
    );
    if (i < 0) return;
    await handler.skipToQueueItem(i);
    await handler.seek(c.etat.position);
    if (!c.etat.pause) await handler.play();
  }

  void _lacher() {
    _sonde?.cancel();
    _sonde = null;
    state = null;
  }
}

// ── La télé, récepteur ───────────────────────────────────────────────────────

/// Le récepteur de la télé : vit tant que la coque télé est ouverte.
class Recepteur {
  Recepteur._(this._h);

  static Recepteur? instance;

  final GullifyAudioHandler _h;
  HttpServer? _serveur;
  nsd.Registration? _annonce;
  String? nomAnnonce;

  /// Qui a envoyé ce qui joue (« Maxime ») ; vide quand c'est la télé elle-même.
  final de = ValueNotifier<String>('');

  /// Appelé quand un téléphone lance une file : la coque ouvre le lecteur.
  void Function()? ouvrirLecteur;

  static Future<Recepteur?> demarrer(GullifyAudioHandler handler, String nom) async {
    if (kIsWeb) return null;
    final r = Recepteur._(handler);
    try {
      r._serveur = await HttpServer.bind(InternetAddress.anyIPv4, kEcoutePort, shared: true);
    } catch (e) {
      debugPrint('Écouter sur… : port $kEcoutePort indisponible — $e');
      return null;
    }
    r._serveur!.listen(r._servir, onError: (_) {});
    try {
      r._annonce = await nsd.register(
        nsd.Service(
          name: nom,
          type: kEcouteType,
          port: kEcoutePort,
          txt: {
            'v': Uint8List.fromList(utf8.encode('1')),
            'genre': Uint8List.fromList(utf8.encode('tv')),
          },
        ),
      );
      r.nomAnnonce = r._annonce?.service.name ?? nom;
    } catch (e) {
      debugPrint('Écouter sur… : annonce impossible — $e');
    }
    instance = r;
    return r;
  }

  Future<void> arreter() async {
    if (instance == this) instance = null;
    final a = _annonce;
    _annonce = null;
    if (a != null) await nsd.unregister(a).catchError((_) {});
    await _serveur?.close(force: true);
    _serveur = null;
  }

  static bool _local(InternetAddress a) {
    if (a.isLoopback || a.isLinkLocal) return true;
    if (a.type == InternetAddressType.IPv4) {
      final b = a.rawAddress;
      return b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168);
    }
    return (a.rawAddress[0] & 0xfe) == 0xfc; // fc00::/7
  }

  Future<void> _servir(HttpRequest req) async {
    final res = req.response;
    Future<void> rendre(int code, Object corps) async {
      res.statusCode = code;
      res.headers.contentType = ContentType.json;
      res.headers.set('Cache-Control', 'no-store');
      res.write(jsonEncode(corps));
      await res.close();
    }

    try {
      final ip = req.connectionInfo?.remoteAddress;
      if (ip == null || !_local(ip)) {
        return rendre(403, {'erreur': 'réseau local seulement'});
      }
      final chemin = req.uri.path;
      if (req.method == 'GET' && chemin == '/etat') {
        return rendre(200, _etatIci());
      }
      if (req.method != 'POST') return rendre(404, {'erreur': 'inconnu'});
      if (req.headers.contentType?.mimeType != 'application/json') {
        return rendre(415, {'erreur': 'JSON attendu'});
      }
      final brut = await utf8.decodeStream(req.take(2000000));
      final corps = jsonDecode(brut);
      if (corps is! Map) return rendre(400, {'erreur': 'objet attendu'});
      if (chemin == '/jouer') {
        await _jouer(Map<String, dynamic>.from(corps));
      } else if (chemin == '/commande') {
        await _geste(corps['geste'], corps['valeur']);
      } else {
        return rendre(404, {'erreur': 'inconnu'});
      }
      return rendre(200, _etatIci());
    } on FormatException catch (e) {
      return rendre(400, {'erreur': e.message});
    } catch (e) {
      return rendre(500, {'erreur': '$e'});
    }
  }

  Future<void> _jouer(Map<String, dynamic> corps) async {
    final file = corps['file'];
    if (file is! List || file.isEmpty || file.length > 500) {
      throw const FormatException('file : de 1 à 500 titres');
    }
    final items = <MediaItem>[];
    for (final t in file) {
      if (t is! Map) throw const FormatException('titre illisible');
      final url = t['url'];
      if (url is! String || !(url.startsWith('https://') || url.startsWith('http://'))) {
        throw const FormatException('adresse refusée');
      }
      String txt(String k) => (t[k] is String) ? (t[k] as String) : '';
      final p = txt('pochette');
      items.add(
        MediaItem(
          id: url,
          title: txt('titre').isEmpty ? 'Sans titre' : txt('titre'),
          artist: txt('artiste').isEmpty ? null : txt('artiste'),
          album: txt('album').isEmpty ? null : txt('album'),
          artUri: p.startsWith('http') ? Uri.tryParse(p) : null,
          extras: const {'ecoute': true},
        ),
      );
    }
    final index = corps['index'] is int ? corps['index'] as int : 0;
    final pos = corps['position'] is num ? corps['position'] as num : 0;
    final qui = corps['de'];
    de.value = qui is String ? (qui.length > 80 ? qui.substring(0, 80) : qui) : '';
    await _h.playEcoute(
      items,
      startIndex: index,
      startPosition: Duration(milliseconds: (pos * 1000).round()),
    );
    ouvrirLecteur?.call();
  }

  Future<void> _geste(Object? geste, Object? valeur) async {
    final h = _h;
    switch (geste) {
      case 'pause':
        await h.pause();
      case 'reprendre':
        await h.play();
      case 'suivant':
        await h.skipToNext();
      case 'precedent':
        await h.skipToPrevious();
      case 'aller':
        if (valeur is! int) throw const FormatException('index attendu');
        await h.skipToQueueItem(valeur);
      case 'chercher':
        if (valeur is! num || valeur < 0) throw const FormatException('position invalide');
        await h.seek(Duration(milliseconds: (valeur * 1000).round()));
      case 'volume':
        break; // la télé garde le volume de sa télécommande
      case 'arreter':
        de.value = '';
        await h.stop();
      default:
        throw const FormatException('geste inconnu');
    }
  }

  /// L'état d'ici, vu du téléphone. Seule une file envoyée par un téléphone
  /// compte comme « actif » : la télé qui joue pour elle-même n'est pas prise.
  Map<String, dynamic> _etatIci() {
    final h = _h;
    final items = h.queue.value;
    final lecture = h.playbackState.value;
    final courant = h.mediaItem.value;
    final actif = de.value.isNotEmpty &&
        courant != null &&
        courant.extras?['ecoute'] == true &&
        lecture.processingState != AudioProcessingState.idle;
    final index = actif ? items.indexWhere((i) => i.id == courant.id) : -1;
    return {
      'v': 1,
      'nom': nomAnnonce ?? '',
      'genre': 'tv',
      'de': actif ? de.value : '',
      'file': actif
          ? [
              for (final i in items)
                {
                  'titre': i.title,
                  'artiste': i.artist ?? '',
                  'album': i.album ?? '',
                  'pochette': i.artUri?.toString() ?? '',
                },
            ]
          : const [],
      'index': index,
      'position': actif ? lecture.position.inMilliseconds / 1000 : 0,
      'duree': actif ? (courant.duration?.inMilliseconds ?? 0) / 1000 : 0,
      'pause': actif ? !lecture.playing : true,
      'volume': null,
      'actif': actif,
    };
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    this.horloge,
    this.avec = const [],
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
      horloge: (j['horloge'] as num?)?.toDouble(),
      avec: [for (final n in (j['avec'] as List? ?? const [])) if (n is String) n],
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

  /// L'heure de l'appareil (secondes) au moment de sa réponse ; null avant
  /// GulliOS 1.140 / app 3.100.0 (pas de départ synchronisé).
  final double? horloge;

  /// Les autres appareils du groupe (noms), pour la pastille.
  final List<String> avec;

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
  // Charger une longue file peut prendre plus de 6 s (mpv qui démarre) : un
  // délai trop court faisait croire à un échec et renvoyer pendant le chargement.
  final r = await _dio.post<dynamic>(
    '${a.base}$chemin',
    data: corps,
    options: chemin == '/jouer'
        ? Options(receiveTimeout: const Duration(seconds: 25))
        : null,
  );
  return EtatDistant.fromJson(Map<String, dynamic>.from(r.data as Map));
}

// ── La découverte ────────────────────────────────────────────────────────────

/// Les appareils du Wi-Fi, tant que la liste « Écouter sur… » est ouverte.
final appareilsProvider =
    NotifierProvider.autoDispose<Appareils, List<Appareil>>(Appareils.new);

class Appareils extends Notifier<List<Appareil>> {
  nsd.Discovery? _decouverte;
  RawDatagramSocket? _socket;
  Timer? _relance;
  bool _fini = false;

  @override
  List<Appareil> build() {
    _fini = false;
    ref.onDispose(() {
      _fini = true;
      _relance?.cancel();
      _socket?.close();
      _socket = null;
      final d = _decouverte;
      _decouverte = null;
      if (d != null) unawaited(nsd.stopDiscovery(d).catchError((_) {}));
    });
    if (!kIsWeb) {
      unawaited(_demarrerMdns());
      unawaited(_demarrerNsd());
      unawaited(_balayer());
    }
    return const [];
  }

  /// Le filet (3.99.1) : si le Wi-Fi ne laisse passer aucune annonce (multicast
  /// filtré par la borne ou le téléphone), on demande /etat à chaque adresse du
  /// réseau du téléphone (/24), 32 à la fois, 600 ms chacune : ~3 s.
  Future<void> _balayer() async {
    try {
      final ici = <String>{};
      final reseaux = <String>{};
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in i.addresses) {
          final b = a.rawAddress;
          final prive = b[0] == 10 ||
              (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
              (b[0] == 192 && b[1] == 168);
          if (!prive) continue;
          ici.add(a.address);
          reseaux.add('${b[0]}.${b[1]}.${b[2]}');
        }
      }
      final cibles = [
        for (final r in reseaux)
          for (var h = 1; h < 255; h++)
            if (!ici.contains('$r.$h')) '$r.$h',
      ];
      final rapide = Dio(
        BaseOptions(
          connectTimeout: const Duration(milliseconds: 600),
          receiveTimeout: const Duration(milliseconds: 1500),
          responseType: ResponseType.json,
        ),
      );
      for (var k = 0; k < cibles.length && !_fini; k += 32) {
        await Future.wait([
          for (final ip in cibles.skip(k).take(32))
            rapide
                .get<dynamic>('http://$ip:$kEcoutePort/etat')
                .then((r) {
                  final e = EtatDistant.fromJson(
                    Map<String, dynamic>.from(r.data as Map),
                  );
                  if (e.nom.isEmpty) return;
                  _ajouter(
                    Appareil(
                      cle: e.nom,
                      nom: e.nom,
                      hote: ip,
                      port: kEcoutePort,
                      genre: e.genre.isEmpty ? 'gullios' : e.genre,
                    ),
                  );
                })
                .catchError((_) {}),
        ]);
      }
      rapide.close(force: true);
    } catch (e) {
      debugPrint('Écouter sur… : balayage impossible — $e');
    }
  }

  /// Notre propre question mDNS (3.99.1), sans passer par Android : envoyée
  /// depuis un port quelconque, elle reçoit sa réponse en direct (« legacy
  /// unicast », RFC 6762 § 6.7) — pas besoin d'écouter le multicast, que bien
  /// des téléphones filtrent. C'est elle qui trouve les GulliOS ; la
  /// découverte d'Android (nsd) reste en parallèle.
  Future<void> _demarrerMdns() async {
    try {
      final so = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (_fini) {
        so.close();
        return;
      }
      _socket = so;
      so.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = so.receive();
        if (d == null) return;
        for (final a in lireReponseMdns(d.data, d.address.address)) {
          _ajouter(a);
        }
      });
      final question = questionMdns(kEcouteType);
      void poser() {
        try {
          so.send(question, InternetAddress('224.0.0.251'), 5353);
        } catch (_) {}
      }

      poser();
      _relance = Timer.periodic(const Duration(seconds: 3), (_) => poser());
    } catch (e) {
      debugPrint('Écouter sur… : question mDNS impossible — $e');
    }
  }

  Future<void> _demarrerNsd() async {
    try {
      final d = await nsd.startDiscovery(kEcouteType);
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
      debugPrint('Écouter sur… : découverte Android impossible — $e');
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
    final g = s.txt?['genre'];
    _ajouter(
      Appareil(
        cle: s.name!,
        nom: s.name!,
        hote: hote,
        port: s.port!,
        genre: g == null ? 'gullios' : utf8.decode(g, allowMalformed: true),
      ),
    );
  }

  void _ajouter(Appareil a) {
    if (_fini) return;
    // Soi-même (la télé qui s'annonce, vue d'elle-même) : pas dans la liste.
    if (Recepteur.instance?.nomAnnonce == a.cle) return;
    // Même adresse sous un autre nom (annonce Android, la nôtre, balayage) :
    // c'est le même appareil, on garde le premier nom.
    if (state.any((x) => x.cle != a.cle && x.base == a.base)) return;
    final deja = state.where((x) => x.cle == a.cle).firstOrNull;
    // Déjà là et qui répond : rien à refaire (la question repart toutes les 3 s).
    if (deja != null && deja.dispo && deja.hote == a.hote) return;
    if (deja == null || deja.hote != a.hote) {
      state = [for (final x in state) if (x.cle != a.cle) x, a];
    }
    unawaited(_sonder(deja != null && deja.hote == a.hote ? deja : a));
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

// ── mDNS, juste ce qu'il faut ────────────────────────────────────────────────

/// La question PTR « qui offre ce service ? », bit QU posé.
Uint8List questionMdns(String type) {
  final b = BytesBuilder()..add([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
  for (final etiquette in '$type.local'.split('.')) {
    final e = utf8.encode(etiquette);
    b
      ..addByte(e.length)
      ..add(e);
  }
  b.add([0, 0, 12, 0x80, 1]); // PTR, classe IN + bit « réponse directe »
  return b.toBytes();
}

/// Les appareils d'une réponse mDNS : instance (PTR), port (SRV), genre (TXT),
/// adresse (A, sinon celle de l'expéditeur). Une réponse mal formée ne donne
/// rien.
List<Appareil> lireReponseMdns(Uint8List d, String expediteur) {
  try {
    if (d.length < 12) return const [];
    int u16(int i) => (d[i] << 8) | d[i + 1];
    final n = u16(4) + u16(6) + u16(8) + u16(10);
    final qd = u16(4);

    // Un nom, compression comprise ; rend (nom, position après).
    (String, int) nom(int i) {
      final parts = <String>[];
      var fin = -1;
      for (var sauts = 0; sauts < 20; sauts++) {
        final l = d[i];
        if (l == 0) {
          i++;
          break;
        }
        if (l & 0xc0 == 0xc0) {
          if (fin < 0) fin = i + 2;
          i = ((l & 0x3f) << 8) | d[i + 1];
          continue;
        }
        parts.add(utf8.decode(d.sublist(i + 1, i + 1 + l), allowMalformed: true));
        i += 1 + l;
      }
      return (parts.join('.'), fin >= 0 ? fin : i);
    }

    var i = 12;
    for (var q = 0; q < qd; q++) {
      i = nom(i).$2 + 4;
    }
    final instances = <String>[];
    final ports = <String, int>{};
    final genres = <String, String>{};
    final cibles = <String, String>{};
    final adresses = <String, String>{};
    final suffixe = '.$kEcouteType.local'.toLowerCase();
    for (var r = 0; r < n - qd && i < d.length; r++) {
      final (proprio, j) = nom(i);
      final type = u16(j);
      final longueur = u16(j + 8);
      final debut = j + 10;
      final cle = proprio.toLowerCase();
      if (type == 12 && cle == '${kEcouteType.toLowerCase()}.local') {
        final inst = nom(debut).$1;
        if (inst.toLowerCase().endsWith(suffixe)) instances.add(inst);
      } else if (type == 33) {
        ports[cle] = u16(debut + 4);
        cibles[cle] = nom(debut + 6).$1.toLowerCase();
      } else if (type == 16) {
        var k = debut;
        while (k < debut + longueur) {
          final l = d[k];
          final t = utf8.decode(d.sublist(k + 1, k + 1 + l), allowMalformed: true);
          if (t.startsWith('genre=')) genres[cle] = t.substring(6);
          k += 1 + l;
        }
      } else if (type == 1 && longueur == 4) {
        adresses[cle] = d.sublist(debut, debut + 4).join('.');
      }
      i = debut + longueur;
    }
    return [
      for (final inst in instances)
        Appareil(
          cle: inst.substring(0, inst.length - suffixe.length),
          nom: inst.substring(0, inst.length - suffixe.length),
          hote: adresses[cibles[inst.toLowerCase()]] ?? expediteur,
          port: ports[inst.toLowerCase()] ?? kEcoutePort,
          genre: genres[inst.toLowerCase()] ?? 'gullios',
        ),
    ];
  } catch (_) {
    return const [];
  }
}

// ── Le téléphone, télécommande ───────────────────────────────────────────────

/// Un appareil du groupe, son dernier état, et l'écart de son horloge avec
/// celle du téléphone (secondes ; null s'il ne sait pas partir à l'heure).
class Membre {
  const Membre(this.appareil, this.etat, this.ecart);
  final Appareil appareil;
  final EtatDistant etat;
  final double? ecart;

  Membre avecEtat(EtatDistant e) => Membre(appareil, e, ecart);
}

/// Où joue la musique : un ou plusieurs appareils (3.100.0). Le premier mène :
/// c'est son titre et sa position qu'on affiche.
class Cible {
  const Cible(this.membres);
  final List<Membre> membres;

  Appareil get appareil => membres.first.appareil;
  EtatDistant get etat => membres.first.etat;
  List<Appareil> get appareils => [for (final m in membres) m.appareil];
}

/// L'appareil où joue la musique, ou null : elle joue ici.
final cibleProvider = NotifierProvider<CibleNotifier, Cible?>(
  CibleNotifier.new,
);

double _maintenantTel() => DateTime.now().microsecondsSinceEpoch / 1e6;

/// Délai laissé au groupe pour charger avant de partir ensemble.
const _delaiDepart = 1.5;

class CibleNotifier extends Notifier<Cible?> {
  Timer? _sonde;
  final _echecs = <String, int>{};
  int _dernierIndex = -1;

  @override
  Cible? build() {
    ref.onDispose(() => _sonde?.cancel());
    return null;
  }

  /// L'écart d'horloge d'un appareil : son heure moins celle du téléphone au
  /// milieu de l'aller-retour (le meilleur de trois essais).
  Future<(EtatDistant, double?)> _mesurer(Appareil a) async {
    EtatDistant? dernier;
    double? meilleur;
    var plusCourt = double.infinity;
    for (var n = 0; n < 3; n++) {
      final t0 = _maintenantTel();
      final e = await _etat(a);
      final t1 = _maintenantTel();
      dernier = e;
      if (e.horloge == null) break;
      if (t1 - t0 < plusCourt) {
        plusCourt = t1 - t0;
        meilleur = e.horloge! - (t0 + t1) / 2;
      }
    }
    return (dernier!, meilleur);
  }

  /// Envoie la file d'ici à [appareils], au titre et à la seconde où l'on en
  /// est ; ils partent ensemble. Puis ce téléphone se met en pause.
  Future<void> envoyer(List<Appareil> choisis) async {
    // Un même appareil vu sous deux noms (annonce et balayage) ne reçoit
    // qu'un envoi : deux /jouer à la fois mélangeaient sa file.
    final vus = <String>{};
    final appareils = [for (final a in choisis) if (vus.add(a.base)) a];
    if (appareils.isEmpty) return;
    final handler = ref.read(audioHandlerProvider);
    final client = ref.read(apiClientProvider);
    final user = ref.read(authProvider).user;
    // Déjà sur des appareils : on repart de là où ils en sont.
    final avant = state;
    final items = handler.queue.value;
    final lecture = handler.playbackState.value;
    if (items.isEmpty) throw StateError('Rien à envoyer : la file est vide.');
    final courant = handler.mediaItem.value;
    var index = lecture.queueIndex ?? items.indexWhere((i) => i.id == courant?.id);
    if (index < 0 || index >= items.length) index = 0;
    var position = lecture.position.inMilliseconds / 1000;
    if (avant != null && avant.etat.titre != null) {
      final t = avant.etat.titre!;
      final i = items.indexWhere(
        (m) => m.title == t['titre'] && (m.artist ?? '') == t['artiste'],
      );
      if (i >= 0) {
        index = i;
        position = avant.etat.position.inMilliseconds / 1000 + _delaiDepart;
      }
    }

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

    // Ceux qui quittent le groupe s'arrêtent.
    final gardes = {for (final a in appareils) a.cle};
    for (final m in avant?.membres ?? const <Membre>[]) {
      if (!gardes.contains(m.appareil.cle)) {
        unawaited(
          _poster(m.appareil, '/commande', {'geste': 'arreter'}).then(
            (_) {},
            onError: (_) {},
          ),
        );
      }
    }

    final mesures = await Future.wait([
      for (final a in appareils)
        _mesurer(a).then<(EtatDistant, double?)?>((m) => m, onError: (_) => null),
    ]);
    final depart = _maintenantTel() + _delaiDepart;
    final membres = <Membre>[];
    final refus = <String>[];
    await Future.wait([
      for (var k = 0; k < appareils.length; k++)
        () async {
          final a = appareils[k];
          final ecart = mesures[k]?.$2;
          try {
            final e = await _poster(a, '/jouer', {
              'de': de,
              'avec': [for (final b in appareils) if (b.cle != a.cle) b.nom],
              'file': file,
              'index': nouvelIndex,
              'position': position,
              if (appareils.length > 1 && ecart != null) 'depart': depart + ecart,
            });
            membres.add(Membre(a.avec(dispo: true), e, ecart));
          } catch (_) {
            refus.add(a.nom);
          }
        }(),
    ]);
    if (membres.isEmpty) {
      throw StateError('${refus.join(', ')} n\'a pas pu jouer la musique.');
    }
    // L'ordre choisi est gardé : le premier mène.
    membres.sort(
      (x, y) => appareils.indexWhere((a) => a.cle == x.appareil.cle)
          .compareTo(appareils.indexWhere((a) => a.cle == y.appareil.cle)),
    );
    await handler.pause();
    state = Cible(membres);
    _dernierIndex = nouvelIndex;
    _echecs.clear();
    _sonde?.cancel();
    _sonde = Timer.periodic(const Duration(seconds: 1), (_) => _rafraichir());
    if (refus.isNotEmpty) {
      throw StateError('${refus.join(', ')} n\'a pas répondu ; les autres jouent.');
    }
  }

  Future<void> _rafraichir() async {
    final c = state;
    if (c == null) return;
    final suivants = <Membre>[];
    for (final r in await Future.wait([
      for (final m in c.membres)
        _etat(m.appareil).then<(Membre, EtatDistant?)>(
          (e) => (m, e),
          onError: (_) => (m, null),
        ),
    ])) {
      final (m, e) = r;
      final cle = m.appareil.cle;
      if (e == null) {
        // Injoignable un moment : on le garde 10 s.
        if ((_echecs[cle] = (_echecs[cle] ?? 0) + 1) < 10) suivants.add(m);
        continue;
      }
      _echecs.remove(cle);
      // Quelqu'un d'autre l'a pris, ou il s'est arrêté : il quitte le groupe.
      if (e.actif) suivants.add(m.avecEtat(e));
    }
    if (!identical(state, c)) return;
    if (suivants.isEmpty) {
      _lacher();
      return;
    }
    state = Cible(suivants);
    // Nouveau titre : si le groupe s'est écarté (> 150 ms), on le recale.
    final chef = suivants.first.etat;
    if (chef.index != _dernierIndex) {
      _dernierIndex = chef.index;
      if (suivants.length > 1 && !chef.pause && _ecartDuGroupe(suivants) > 0.15) {
        unawaited(_caler(chef.index, chef.position.inMilliseconds / 1000 + _delaiDepart));
      }
    }
  }

  /// Le plus grand écart de position entre les membres, ramenés à la même
  /// heure du téléphone. 0 si on ne sait pas le calculer.
  double _ecartDuGroupe(List<Membre> ms) {
    final positions = <double>[];
    for (final m in ms) {
      final e = m.etat;
      if (m.ecart == null || e.horloge == null || e.index != ms.first.etat.index) return 0;
      // Position de l'appareil à l'heure t (téléphone) = position + (t - (horloge - écart)).
      positions.add(e.position.inMilliseconds / 1000 - (e.horloge! - m.ecart!));
    }
    positions.sort();
    return positions.isEmpty ? 0 : positions.last - positions.first;
  }

  /// Tout le groupe repart ensemble au titre [index], à [position] (secondes).
  Future<void> _caler(int index, double position) async {
    final c = state;
    if (c == null) return;
    final depart = _maintenantTel() + _delaiDepart;
    await Future.wait([
      for (final m in c.membres)
        (m.ecart == null
                // Un appareil sans départ à l'heure (GulliOS < 1.140) : titre,
                // position, puis on relance — sans ce dernier geste il restait
                // en pause (vu le 2026-11-14, 3.100.0).
                ? _poster(m.appareil, '/commande', {'geste': 'aller', 'valeur': index})
                      .then(
                        (_) => _poster(m.appareil, '/commande', {
                          'geste': 'chercher',
                          'valeur': position,
                        }),
                      )
                      .then(
                        (_) => _poster(m.appareil, '/commande', {'geste': 'reprendre'}),
                      )
                : _poster(m.appareil, '/commande', {
                    'geste': 'caler',
                    'valeur': {
                      'index': index,
                      'position': position,
                      'depart': depart + m.ecart!,
                    },
                  }))
            .then((_) {}, onError: (_) {}),
    ]);
    _dernierIndex = index;
  }

  /// Un geste pour tout le groupe. Seul, un appareil reçoit le geste tel quel ;
  /// à plusieurs, tout ce qui fait repartir passe par un départ commun.
  Future<void> commande(String geste, [Object? valeur]) async {
    final c = state;
    if (c == null) return;
    if (c.membres.length > 1) {
      final e = c.etat;
      final pos = e.position.inMilliseconds / 1000;
      switch (geste) {
        case 'reprendre':
          return _caler(e.index, pos);
        case 'suivant':
          if (e.index + 1 < e.file.length) return _caler(e.index + 1, 0);
          return;
        case 'precedent':
          return _caler(pos > 3 || e.index == 0 ? e.index : e.index - 1, 0);
        case 'chercher':
          if (valeur is num) return _caler(e.index, valeur.toDouble());
          return;
        case 'aller':
          if (valeur is int) return _caler(valeur, 0);
          return;
        case 'volume':
          // « Tous » : le même volume partout où il se règle.
          for (final m in c.membres) {
            if (m.etat.volume != null) unawaited(volume(m.appareil, valeur));
          }
          return;
      }
    }
    await Future.wait([
      for (final m in c.membres)
        _poster(m.appareil, '/commande', {'geste': geste, 'valeur': ?valeur}).then(
          (e) => _remplacer(m.appareil.cle, e),
          onError: (Object e) => debugPrint('Écouter sur… : $geste refusé — $e'),
        ),
    ]);
  }

  /// Le volume d'un seul appareil du groupe.
  Future<void> volume(Appareil a, Object? valeur) async {
    try {
      final e = await _poster(a, '/commande', {'geste': 'volume', 'valeur': valeur});
      _remplacer(a.cle, e);
    } catch (_) {}
  }

  void _remplacer(String cle, EtatDistant e) {
    final c = state;
    if (c == null) return;
    state = Cible([
      for (final m in c.membres) if (m.appareil.cle == cle) m.avecEtat(e) else m,
    ]);
  }

  /// Retire un appareil du groupe (il s'arrête) ; les autres continuent.
  Future<void> retirer(Appareil a) async {
    final c = state;
    if (c == null) return;
    if (c.membres.length == 1) return revenir();
    final restants = [for (final m in c.membres) if (m.appareil.cle != a.cle) m];
    // Plantage vu le 2026-11-14 (3.100.0) : un groupe vidé → Cible([]) → .first.
    if (restants.isEmpty) return revenir();
    state = Cible(restants);
    try {
      await _poster(a, '/commande', {'geste': 'arreter'});
    } catch (_) {}
  }

  /// Revenir à « Ce téléphone » : le groupe s'arrête, la lecture reprend ici
  /// au titre et à la seconde où il en était (si c'est un titre de notre file).
  Future<void> revenir() async {
    final c = state;
    if (c == null) return;
    _lacher();
    final handler = ref.read(audioHandlerProvider);
    await Future.wait([
      for (final m in c.membres)
        _poster(m.appareil, '/commande', {'geste': 'arreter'}).then(
          (_) {},
          onError: (_) {},
        ),
    ]);
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

  /// Les autres appareils du groupe (3.100.0), pour la pastille.
  final avec = ValueNotifier<List<String>>(const []);

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
    final autres = corps['avec'];
    avec.value = [
      if (autres is List)
        for (final n in autres.take(10)) if (n is String) n.length > 60 ? n.substring(0, 60) : n,
    ];
    final depart = _depart(corps['depart']);
    _generation++;
    await _h.playEcoute(
      items,
      startIndex: index,
      startPosition: Duration(milliseconds: (pos * 1000).round()),
      lancer: depart == null,
    );
    if (depart != null) unawaited(_partir(depart));
    ouvrirLecteur?.call();
  }

  /// Plusieurs appareils (3.100.0) : un départ programmé plus ancien que le
  /// dernier ordre est abandonné.
  int _generation = 0;

  /// L'heure de départ (secondes, horloge d'ICI : le téléphone a corrigé
  /// l'écart), ou null.
  static double? _depart(Object? v) => v is num && v > 0 ? v.toDouble() : null;

  static double _maintenant() => DateTime.now().microsecondsSinceEpoch / 1e6;

  /// En pause : attendre que le titre soit prêt (et calé à [position]), puis
  /// lancer à l'heure [depart]. Un départ passé ou à plus de 30 s part tout
  /// de suite.
  Future<void> _partir(double depart, {double? position}) async {
    final g = ++_generation;
    final limite = depart < _maintenant() + 30 ? depart : _maintenant() + 30;
    while (_maintenant() < limite && g == _generation) {
      if (_h.playbackState.value.processingState == AudioProcessingState.ready) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (position != null && g == _generation) {
      await _h.seek(Duration(microseconds: (position * 1e6).round()));
    }
    final reste = depart - _maintenant();
    if (reste > 0 && reste <= 30) {
      await Future<void>.delayed(Duration(microseconds: (reste * 1e6).round()));
    }
    if (g == _generation) await _h.play();
  }

  Future<void> _geste(Object? geste, Object? valeur) async {
    final h = _h;
    if (geste != 'caler') _generation++;
    switch (geste) {
      case 'caler':
        if (valeur is! Map) throw const FormatException('caler : {index, position, depart}');
        final i = valeur['index'];
        final p = valeur['position'];
        final d = _depart(valeur['depart']);
        if (i is! int || i < 0 || i >= h.queue.value.length) {
          throw const FormatException('index hors de la file');
        }
        if (p is! num || p < 0 || d == null) {
          throw const FormatException('position ou départ invalide');
        }
        await h.pause();
        final courant = h.queue.value.indexWhere((m) => m.id == h.mediaItem.value?.id);
        if (courant != i) {
          await h.skipToQueueItem(i);
          await h.pause();
        }
        unawaited(_partir(d, position: p.toDouble()));
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
      'horloge': _maintenant(),
      'avec': actif ? avec.value : const <String>[],
    };
  }
}

import 'dart:convert';

import '../models/game_source.dart';
import 'api_client.dart';

/// Client des parties multijoueur (`/api/v2/party.php`).
///
/// L'hôte crée le salon avec son compte, puis tout se joue avec le jeton de
/// partie qu'il reçoit en retour — le même mécanisme que pour les invités du
/// web. Le serveur fait autorité : l'app ne fait qu'afficher l'état qu'il rend
/// et poster les réponses.

/// Un joueur du salon, tel que le serveur le décrit.
class PartyPlayer {
  const PartyPlayer({
    required this.id,
    required this.name,
    required this.isHost,
    required this.score,
    required this.lives,
    required this.answered,
    this.correct,
    this.gained,
    this.timeline,
  });

  final int id;
  final String name;
  final bool isHost;
  final int score;
  final int lives;

  /// A répondu à la manche en cours (le verdict, lui, reste caché).
  final bool answered;

  /// Verdict de la manche — `null` tant qu'elle n'est pas révélée.
  final bool? correct;
  final int? gained;

  /// Frise chronologique du joueur (Chrono uniquement).
  final List<PartyCard>? timeline;

  static PartyPlayer fromJson(Map<String, dynamic> j, String? Function(String?) abs) =>
      PartyPlayer(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        isHost: j['isHost'] == true,
        score: (j['score'] as num?)?.toInt() ?? 0,
        lives: (j['lives'] as num?)?.toInt() ?? 0,
        answered: j['answered'] == true,
        correct: j['correct'] as bool?,
        gained: (j['gained'] as num?)?.toInt(),
        timeline: j['timeline'] == null
            ? null
            : [
                for (final c in j['timeline'] as List<dynamic>)
                  PartyCard.fromJson(c as Map<String, dynamic>, abs),
              ],
      );
}

/// Une carte posée sur la frise du Chrono.
class PartyCard {
  const PartyCard({
    required this.songId,
    required this.title,
    required this.year,
    this.artist,
    this.artworkUrl,
  });

  final int songId;
  final String title;
  final int year;
  final String? artist;
  final String? artworkUrl;

  static PartyCard fromJson(Map<String, dynamic> j, String? Function(String?) abs) =>
      PartyCard(
        songId: (j['songId'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        year: (j['year'] as num?)?.toInt() ?? 0,
        artist: j['artist'] as String?,
        artworkUrl: abs(j['artworkUrl'] as String?),
      );
}

/// Un message vocal du talkie-walkie, tel que le serveur l'annonce.
///
/// Le son n'est pas dans l'état : on ne reçoit que la fiche, et on va chercher
/// les octets si (et seulement si) on décide de l'écouter.
class PartyVoiceClip {
  const PartyVoiceClip({
    required this.id,
    required this.playerId,
    required this.name,
    required this.ms,
    required this.at,
  });

  final int id;
  final int playerId;

  /// Prénom de celui qui parle.
  final String name;

  /// Durée du message, en millisecondes.
  final int ms;

  /// Horodatage serveur de l'envoi.
  final int at;

  static PartyVoiceClip fromJson(Map<String, dynamic> j) => PartyVoiceClip(
        id: (j['id'] as num?)?.toInt() ?? 0,
        playerId: (j['playerId'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        ms: (j['ms'] as num?)?.toInt() ?? 0,
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

/// Une proposition de réponse (blind test, pochette mystère).
class PartyOption {
  const PartyOption({required this.id, required this.title, this.subtitle});

  final String id;
  final String title;
  final String? subtitle;

  static PartyOption fromJson(Map<String, dynamic> j) => PartyOption(
        id: '${j['id']}',
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String?,
      );
}

/// Un des deux albums d'un duel d'années.
class PartyDuelSide {
  const PartyDuelSide({
    required this.id,
    required this.title,
    this.subtitle,
    this.artworkUrl,
    this.year,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? artworkUrl;

  /// Millésime — `null` tant que la manche n'est pas révélée.
  final int? year;

  static PartyDuelSide fromJson(Map<String, dynamic> j, String? Function(String?) abs) =>
      PartyDuelSide(
        id: '${j['id']}',
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String?,
        artworkUrl: abs(j['artworkUrl'] as String?),
        year: (j['year'] as num?)?.toInt(),
      );
}

/// La manche en cours, telle que le serveur accepte de la montrer.
class PartyRound {
  const PartyRound({
    required this.index,
    required this.kind,
    this.myAnswer,
    this.options = const [],
    this.filePath,
    this.startSec = 0,
    this.artworkUrl,
    this.title,
    this.artist,
    this.albumName,
    this.year,
    this.answerId,
    this.left,
    this.right,
  });

  final int index;

  /// `blind` | `cover` | `duel` | `chrono`.
  final String kind;

  /// Réponse déjà envoyée par ce joueur (`null` = pas encore répondu).
  final String? myAnswer;

  final List<PartyOption> options;

  /// Chemin du morceau — réservé à l'hôte, qui lit l'extrait en direct.
  final String? filePath;
  final int startSec;

  final String? artworkUrl;
  final String? title;
  final String? artist;
  final String? albumName;

  /// Millésime du titre mystère (Chrono, après révélation).
  final int? year;

  /// La bonne réponse — n'arrive qu'une fois la manche révélée.
  final String? answerId;

  final PartyDuelSide? left;
  final PartyDuelSide? right;

  bool get answered => myAnswer != null;

  static PartyRound fromJson(Map<String, dynamic> j, String? Function(String?) abs) =>
      PartyRound(
        index: (j['i'] as num?)?.toInt() ?? 0,
        kind: j['kind'] as String? ?? '',
        myAnswer: j['myAnswer'] as String?,
        options: [
          for (final o in j['options'] as List<dynamic>? ?? [])
            PartyOption.fromJson(o as Map<String, dynamic>),
        ],
        filePath: j['filePath'] as String?,
        startSec: (j['startSec'] as num?)?.toInt() ?? 0,
        artworkUrl: abs(j['artworkUrl'] as String?),
        title: j['title'] as String?,
        artist: j['artist'] as String?,
        albumName: j['albumName'] as String?,
        year: (j['year'] as num?)?.toInt(),
        answerId: j['answerId']?.toString(),
        left: j['left'] == null
            ? null
            : PartyDuelSide.fromJson(j['left'] as Map<String, dynamic>, abs),
        right: j['right'] == null
            ? null
            : PartyDuelSide.fromJson(j['right'] as Map<String, dynamic>, abs),
      );
}

/// L'état complet d'une partie, du salon au classement final.
class PartyState {
  const PartyState({
    required this.code,
    required this.game,
    required this.audioMode,
    required this.status,
    required this.phase,
    required this.version,
    required this.serverNow,
    required this.phaseAt,
    required this.roundMs,
    required this.revealMs,
    required this.roundIndex,
    required this.roundCount,
    required this.maxPlayers,
    required this.players,
    this.turnPlayerId,
    this.meId,
    this.meName,
    this.meIsHost = false,
    this.round,
    this.receivedAt,
    this.voiceClips = const [],
    this.voiceMaxMs = 15000,
    this.voiceMinMs = 350,
  });

  final String code;

  /// `blind` | `cover` | `duel` | `chrono`.
  final String game;

  /// `host` (l'audio ne sort que chez l'hôte) ou `guests` (chacun écoute).
  final String audioMode;

  /// `lobby` | `playing` | `finished`.
  final String status;

  /// `lobby` | `guessing` | `revealed` | `finished`.
  final String phase;

  final int version;

  /// Horloge du serveur au moment de la réponse, et début de la phase — c'est
  /// le serveur qui tient le chrono, l'app se contente de le rejouer.
  final int serverNow;
  final int phaseAt;
  final int roundMs;
  final int revealMs;

  final int roundIndex;
  final int roundCount;
  final int maxPlayers;
  final List<PartyPlayer> players;
  final int? turnPlayerId;
  final int? meId;
  final String? meName;
  final bool meIsHost;
  final PartyRound? round;

  /// Horloge locale à la réception, pour recaler le décompte sans réseau.
  final DateTime? receivedAt;

  /// Les messages vocaux encore écoutables, du plus ancien au plus récent.
  final List<PartyVoiceClip> voiceClips;

  /// Bornes du talkie-walkie, dictées par le serveur.
  final int voiceMaxMs;
  final int voiceMinMs;

  bool get isLobby => status == 'lobby';
  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished';
  bool get isRevealed => phase == 'revealed' || isFinished;
  bool get guestsHearAudio => audioMode == 'guests';
  bool get myTurn => turnPlayerId != null && turnPlayerId == meId;

  PartyPlayer? get me {
    for (final p in players) {
      if (p.id == meId) return p;
    }
    return null;
  }

  PartyPlayer? playerById(int? id) {
    if (id == null) return null;
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Joueurs du plus fort au plus faible.
  List<PartyPlayer> get ranking =>
      [...players]..sort((a, b) => b.score.compareTo(a.score));

  /// Temps restant dans la phase, recalé sur l'horloge du serveur.
  Duration get remaining {
    final total = phase == 'revealed' ? revealMs : roundMs;
    final offset = serverNow - (receivedAt?.millisecondsSinceEpoch ?? serverNow);
    final elapsed = DateTime.now().millisecondsSinceEpoch + offset - phaseAt;
    final left = total - elapsed;
    return Duration(milliseconds: left < 0 ? 0 : left);
  }

  double get progress {
    final total = phase == 'revealed' ? revealMs : roundMs;
    if (total <= 0) return 0;
    return (remaining.inMilliseconds / total).clamp(0.0, 1.0);
  }

  static PartyState fromJson(Map<String, dynamic> j, String? Function(String?) abs) {
    final me = j['me'] as Map<String, dynamic>?;
    final voice = j['voice'] as Map<String, dynamic>?;
    return PartyState(
      code: j['code'] as String? ?? '',
      game: j['game'] as String? ?? '',
      audioMode: j['audioMode'] as String? ?? 'host',
      status: j['status'] as String? ?? 'lobby',
      phase: j['phase'] as String? ?? 'lobby',
      version: (j['version'] as num?)?.toInt() ?? 0,
      serverNow: (j['serverNow'] as num?)?.toInt() ?? 0,
      phaseAt: (j['phaseAt'] as num?)?.toInt() ?? 0,
      roundMs: (j['roundMs'] as num?)?.toInt() ?? 20000,
      revealMs: (j['revealMs'] as num?)?.toInt() ?? 4500,
      roundIndex: (j['roundIndex'] as num?)?.toInt() ?? 0,
      roundCount: (j['roundCount'] as num?)?.toInt() ?? 0,
      maxPlayers: (j['maxPlayers'] as num?)?.toInt() ?? 12,
      turnPlayerId: (j['turnPlayerId'] as num?)?.toInt(),
      meId: (me?['id'] as num?)?.toInt(),
      meName: me?['name'] as String?,
      meIsHost: me?['isHost'] == true,
      players: [
        for (final p in j['players'] as List<dynamic>? ?? [])
          PartyPlayer.fromJson(p as Map<String, dynamic>, abs),
      ],
      round: j['round'] == null
          ? null
          : PartyRound.fromJson(j['round'] as Map<String, dynamic>, abs),
      receivedAt: DateTime.now(),
      voiceClips: [
        for (final c in voice?['clips'] as List<dynamic>? ?? [])
          PartyVoiceClip.fromJson(c as Map<String, dynamic>),
      ],
      voiceMaxMs: (voice?['maxMs'] as num?)?.toInt() ?? 15000,
      voiceMinMs: (voice?['minMs'] as num?)?.toInt() ?? 350,
    );
  }
}

/// Ce que l'hôte reçoit en créant un salon.
class PartyTicket {
  const PartyTicket({
    required this.code,
    required this.token,
    required this.url,
    required this.state,
  });

  final String code;
  final String token;

  /// Le lien à envoyer par SMS.
  final String url;
  final PartyState state;
}

class PartyRepository {
  PartyRepository(this._client);

  final ApiClient _client;

  /// Le serveur rend les images en chemin relatif à sa racine
  /// (`serve_image.php?album_id=…`) : on les rend absolues pour l'app.
  String? _abs(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return _client.resourceUrl(url);
  }

  PartyState _state(dynamic data) =>
      PartyState.fromJson(data as Map<String, dynamic>, _abs);

  /// Crée un salon. `audioMode` : `host` ou `guests`. `source` restreint le
  /// vivier des manches à la bibliothèque de l'hôte (genres, playlists,
  /// favoris) — c'est elle qui fournit la musique de la partie.
  Future<PartyTicket> create({
    required String game,
    required String audioMode,
    GameSource source = GameSource.all,
    String? name,
  }) async {
    final data = await _client.post(
      'party.php',
      query: {'action': 'create'},
      body: {
        'game': game,
        'audioMode': audioMode,
        'source': source.toApi(),
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      },
    ) as Map<String, dynamic>;
    return PartyTicket(
      code: data['code'] as String,
      token: data['token'] as String,
      // Le serveur devine son URL publique ; celle que l'app connaît est plus
      // sûre (c'est celle que l'utilisateur a saisie au moment de se connecter).
      url: '${_client.serverUrl()}/j/${data['code']}',
      state: _state(data['state']),
    );
  }

  Future<PartyState> state(String code, String token) async => _state(
        await _client.get('party.php', query: {
          'action': 'state',
          'code': code,
          'token': token,
        }),
      );

  Future<PartyState> start(String code, String token) async => _state(
        await _client.post(
          'party.php',
          query: {'action': 'start'},
          body: {'code': code, 'token': token},
        ),
      );

  Future<PartyState> answer(String code, String token, String answer) async =>
      _state(
        await _client.post(
          'party.php',
          query: {'action': 'answer'},
          body: {'code': code, 'token': token, 'answer': answer},
        ),
      );

  Future<PartyState> skip(String code, String token) async => _state(
        await _client.post(
          'party.php',
          query: {'action': 'skip'},
          body: {'code': code, 'token': token},
        ),
      );

  /// Envoie un message vocal au salon et renvoie son identifiant.
  ///
  /// Le son part en une fois, encodé en base64 : c'est un message, pas un flux
  /// — les autres joueurs l'entendront à leur prochain sondage.
  Future<int> sendVoice(
    String code,
    String token, {
    required List<int> bytes,
    required String mime,
    required int ms,
  }) async {
    final data = await _client.post(
      'party.php',
      query: {'action': 'voice'},
      body: {
        'code': code,
        'token': token,
        'audio': base64Encode(bytes),
        'mime': mime,
        'ms': ms,
      },
    ) as Map<String, dynamic>;
    return (data['id'] as num?)?.toInt() ?? 0;
  }

  /// L'adresse d'écoute d'un message vocal (le jeton de partie fait l'accès).
  String voiceClipUrl(String code, String token, int id) => _client.resourceUrl(
        'api/v2/party.php?action=voiceclip'
        '&code=${Uri.encodeQueryComponent(code)}'
        '&token=${Uri.encodeQueryComponent(token)}'
        '&id=$id',
      );

  /// Ferme le salon : le lien envoyé par SMS ne répond plus.
  Future<void> close(String code, String token) => _client.post(
        'party.php',
        query: {'action': 'close'},
        body: {'code': code, 'token': token},
      );
}

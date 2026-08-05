import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../api/party_repository.dart';
import '../audio/tuned_player.dart';
import 'party.dart';

/// Talkie-walkie des parties multijoueur.
///
/// On ne tient pas de canal ouvert en permanence : chacun maintient le bouton,
/// parle, relâche — le message part en entier et les autres l'entendent au
/// sondage suivant. C'est ce qui permet de se parler avec des invités qui
/// n'ont qu'un lien dans leur navigateur, sans rien installer et sans serveur
/// de relais temps réel.

/// Un message qu'on vient d'enregistrer, prêt à partir.
class VoiceTake {
  const VoiceTake({required this.bytes, required this.mime, required this.ms});

  final List<int> bytes;
  final String mime;
  final int ms;
}

/// Le micro, vu par le talkie-walkie (l'implémentation réelle est plus bas ;
/// les tests en fournissent une autre).
abstract class VoiceRecorder {
  /// Demande l'autorisation si besoin. `false` = pas de micro, on n'insiste pas.
  Future<bool> ensurePermission();

  Future<void> start();

  /// Referme le micro et rend ce qui a été capté (`null` si rien).
  Future<VoiceTake?> stop();

  Future<void> dispose();
}

/// Le haut-parleur, vu par le talkie-walkie. `play` ne rend la main qu'une fois
/// le message écouté jusqu'au bout.
abstract class VoiceSpeaker {
  Future<void> play(String url);

  Future<void> stop();

  Future<void> dispose();
}

// ─────────────────────────────────────────────────────── implémentations ──

/// Micro de l'appareil : AAC mono 32 kbit/s dans un conteneur MP4 — assez bon
/// pour la parole, assez petit pour partir en 4G, et lisible aussi bien par
/// l'app que par les navigateurs des invités.
class DeviceVoiceRecorder implements VoiceRecorder {
  DeviceVoiceRecorder();

  static const _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 32000,
    sampleRate: 22050,
    numChannels: 1,
    // L'extrait de la manche sort souvent du haut-parleur juste à côté : sans
    // ces trois-là, on se réenregistre la musique par-dessus la voix.
    echoCancel: true,
    noiseSuppress: true,
    autoGain: true,
  );

  final AudioRecorder _recorder = AudioRecorder();
  String? _path;
  DateTime? _startedAt;

  @override
  Future<bool> ensurePermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/party_talk.m4a';
    // Un reste de message précédent fausserait la lecture si l'encodeur
    // échouait sans rien écrire.
    try {
      final old = File(path);
      if (old.existsSync()) await old.delete();
    } catch (_) {}
    await _recorder.start(_config, path: path);
    _path = path;
    _startedAt = DateTime.now();
  }

  @override
  Future<VoiceTake?> stop() async {
    final startedAt = _startedAt;
    _startedAt = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    path ??= _path;
    _path = null;
    if (path == null || startedAt == null) return null;

    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      await file.delete();
      if (bytes.isEmpty) return null;
      return VoiceTake(
        bytes: bytes,
        mime: 'audio/mp4',
        ms: DateTime.now().difference(startedAt).inMilliseconds,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}

/// Lecteur des messages : il ne touche pas au lecteur de musique, ni au lecteur
/// d'extraits de la manche — une voix passe *par-dessus* l'extrait, il lui faut
/// donc un son à lui pendant qu'elle parle. Il l'emprunte à la réserve commune
/// au premier message et le rend en se taisant (tuned_player.dart) : hors des
/// parties, le talkie-walkie ne garde aucun lecteur allumé.
class JustAudioVoiceSpeaker implements VoiceSpeaker {
  PlayerLease? _lease;

  @override
  Future<void> play(String url) async {
    final lease = _lease ??= leaseGullifyPlayer(use: PlayerUse.snippet);
    try {
      await lease.player.setUrl(url);
      // Coupé pendant le chargement (haut-parleur éteint, salon quitté) : le
      // lecteur est rendu, on le laisse à qui l'a repris.
      if (!identical(_lease, lease)) return;
      // `play()` ne rend la main qu'à la fin du message : c'est ce qui enchaîne
      // les messages un par un plutôt que tous ensemble.
      await lease.player.play();
    } catch (_) {
      // Un message illisible (expiré, réseau coupé) ne doit pas bloquer la file.
    }
  }

  @override
  Future<void> stop() async {
    final lease = _lease;
    _lease = null;
    // Rendre le lecteur l'arrête : le `play()` du message en cours se referme,
    // et la file des messages reprend son cours.
    await lease?.give();
  }

  @override
  Future<void> dispose() => stop();
}

// ──────────────────────────────────────────────────────────── réception ──

/// Trie les messages entrants : ceux des autres, jamais deux fois, et jamais
/// l'historique du salon pour qui arrive en cours de route.
///
/// C'est volontairement une classe à part, sans Riverpod ni audio : toute la
/// règle du « qu'est-ce qu'on écoute » se teste ainsi sans appareil.
class VoiceInbox {
  int _lastId = 0;
  bool _primed = false;
  String? _code;

  /// Le dernier message pris en compte (les plus anciens sont oubliés).
  int get lastId => _lastId;

  /// Les messages à écouter, dans l'ordre d'arrivée.
  List<PartyVoiceClip> accept(PartyState party) {
    // Changement de salon : on repart d'une page blanche.
    if (_code != party.code) {
      _code = party.code;
      _primed = false;
      _lastId = 0;
    }

    final fresh = <PartyVoiceClip>[];
    for (final clip in party.voiceClips) {
      if (clip.id > _lastId) {
        if (_primed && clip.playerId != party.meId) fresh.add(clip);
        _lastId = clip.id;
      }
    }
    // Le premier état reçu ne sert qu'à poser le repère : arriver dans un salon
    // ne doit pas déclencher la lecture de tout ce qui s'y est dit avant.
    _primed = true;
    return fresh;
  }

  void reset() {
    _lastId = 0;
    _primed = false;
    _code = null;
  }
}

// ──────────────────────────────────────────────────────────────── état ──

class PartyVoiceState {
  const PartyVoiceState({
    this.recording = false,
    this.arming = false,
    this.speakerOn = true,
    this.micDenied = false,
    this.message,
    this.speakingName,
    this.startedAt,
  });

  /// Le micro est ouvert : ça enregistre.
  final bool recording;

  /// Le micro est en train de s'ouvrir (autorisation, démarrage).
  final bool arming;

  /// On écoute les autres (sinon les messages sont ignorés).
  final bool speakerOn;

  /// L'autorisation micro a été refusée.
  final bool micDenied;

  /// Message passager affiché sous le bouton (envoi, erreur).
  final String? message;

  /// Le prénom de celui qu'on est en train d'écouter.
  final String? speakingName;

  final DateTime? startedAt;

  bool get busy => recording || arming;
  bool get listening => speakingName != null;

  PartyVoiceState copyWith({
    bool? recording,
    bool? arming,
    bool? speakerOn,
    bool? micDenied,
    String? message,
    String? speakingName,
    DateTime? startedAt,
    bool clearMessage = false,
    bool clearSpeaking = false,
    bool clearStartedAt = false,
  }) =>
      PartyVoiceState(
        recording: recording ?? this.recording,
        arming: arming ?? this.arming,
        speakerOn: speakerOn ?? this.speakerOn,
        micDenied: micDenied ?? this.micDenied,
        message: clearMessage ? null : (message ?? this.message),
        speakingName: clearSpeaking ? null : (speakingName ?? this.speakingName),
        startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      );
}

/// Fournisseurs remplaçables : les tests injectent un micro et un haut-parleur
/// de papier.
final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final recorder = DeviceVoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

final voiceSpeakerProvider = Provider<VoiceSpeaker>((ref) {
  final speaker = JustAudioVoiceSpeaker();
  ref.onDispose(speaker.dispose);
  return speaker;
});

class PartyVoiceController extends Notifier<PartyVoiceState> {
  final VoiceInbox _inbox = VoiceInbox();
  final List<PartyVoiceClip> _queue = [];

  Timer? _limit;
  Timer? _clearMessage;
  bool _draining = false;
  bool _disposed = false;

  @override
  PartyVoiceState build() {
    // Le talkie-walkie suit la partie : chaque état apporte les messages reçus.
    ref.listen<PartySession>(partyProvider, (_, next) {
      final party = next.state;
      if (party == null) {
        // Salon fermé (ou perdu) : plus rien à écouter.
        _inbox.reset();
        _queue.clear();
        _speaker.stop();
        return;
      }
      _receive(party);
    });
    ref.onDispose(() {
      _disposed = true;
      _limit?.cancel();
      _clearMessage?.cancel();
    });
    return const PartyVoiceState();
  }

  VoiceRecorder get _recorder => ref.read(voiceRecorderProvider);
  VoiceSpeaker get _speaker => ref.read(voiceSpeakerProvider);

  void _set(PartyVoiceState next) {
    if (_disposed) return;
    state = next;
  }

  void _say(String? message) {
    _clearMessage?.cancel();
    if (message == null) {
      _set(state.copyWith(clearMessage: true));
      return;
    }
    _set(state.copyWith(message: message));
    _clearMessage = Timer(const Duration(milliseconds: 2400), () {
      if (state.message == message) _set(state.copyWith(clearMessage: true));
    });
  }

  // ── parler ──

  /// Ouvre le micro (au premier appui, Android demande l'autorisation).
  Future<void> startTalking() async {
    if (state.busy) return;
    _set(state.copyWith(arming: true, clearMessage: true));

    final allowed = await _recorder.ensurePermission();
    if (!allowed) {
      _set(state.copyWith(arming: false, micDenied: true));
      _say('Micro refusé — autorise-le dans les réglages');
      return;
    }
    // Relâché pendant la demande d'autorisation : on n'enregistre pas.
    if (!state.arming) return;

    try {
      await _recorder.start();
    } catch (_) {
      _set(state.copyWith(arming: false));
      _say('Micro indisponible');
      return;
    }
    if (!state.arming) {
      // Relâché pendant le démarrage : on referme aussitôt.
      await _recorder.stop();
      return;
    }

    _set(state.copyWith(
      arming: false,
      recording: true,
      micDenied: false,
      startedAt: DateTime.now(),
      clearMessage: true,
    ));

    final max = ref.read(partyProvider).state?.voiceMaxMs ?? 15000;
    _limit?.cancel();
    _limit = Timer(Duration(milliseconds: max), stopTalking);
  }

  /// Referme le micro et envoie le message au salon.
  Future<void> stopTalking() async {
    _limit?.cancel();
    _limit = null;
    if (state.arming && !state.recording) {
      // Appui trop bref : le micro n'était pas encore ouvert.
      _set(state.copyWith(arming: false, clearStartedAt: true));
      return;
    }
    if (!state.recording) return;
    _set(state.copyWith(recording: false, clearStartedAt: true));

    final take = await _recorder.stop();
    final session = ref.read(partyProvider);
    final party = session.state;
    final code = session.code, token = session.token;
    if (take == null || code == null || token == null) return;
    if (take.ms < (party?.voiceMinMs ?? 350)) return;

    _say('Envoi…');
    try {
      await ref.read(partyRepositoryProvider).sendVoice(
            code,
            token,
            bytes: take.bytes,
            mime: take.mime,
            ms: take.ms,
          );
      _say('Envoyé');
      // Le message revient dans l'état suivant : on ne se le fait pas rejouer.
      await ref.read(partyProvider.notifier).refresh();
    } catch (_) {
      _say('Message non envoyé');
    }
  }

  // ── écouter ──

  void toggleSpeaker() {
    final on = !state.speakerOn;
    _set(state.copyWith(speakerOn: on));
    if (!on) {
      _queue.clear();
      _speaker.stop();
    }
  }

  void _receive(PartyState party) {
    final fresh = _inbox.accept(party);
    if (fresh.isEmpty || !state.speakerOn) return;
    _queue.addAll(fresh);
    unawaited(_drain());
  }

  /// Joue les messages un par un, dans l'ordre où ils ont été dits.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && state.speakerOn && !_disposed) {
        final clip = _queue.removeAt(0);
        final session = ref.read(partyProvider);
        final code = session.code, token = session.token;
        if (code == null || token == null) break;
        _set(state.copyWith(speakingName: clip.name.isEmpty ? '…' : clip.name));
        await _speaker.play(
          ref.read(partyRepositoryProvider).voiceClipUrl(code, token, clip.id),
        );
      }
    } finally {
      _draining = false;
      _set(state.copyWith(clearSpeaking: true));
    }
  }
}

final partyVoiceProvider =
    NotifierProvider<PartyVoiceController, PartyVoiceState>(
  PartyVoiceController.new,
);

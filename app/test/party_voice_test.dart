// Talkie-walkie des parties : ce que l'app fait des messages vocaux.
//
// Rien de tout ça ne demande de micro ni de haut-parleur — c'est justement le
// but de VoiceInbox : la règle du « qu'est-ce qu'on écoute, et une seule fois »
// se vérifie sans appareil.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/party_repository.dart';
import 'package:gullify/screens/games/party_talk.dart';
import 'package:gullify/state/party_voice.dart';
import 'package:gullify/theme.dart';

String? _abs(String? u) =>
    u == null || u.isEmpty ? null : 'https://example.test/$u';

Map<String, dynamic> _clip(int id, int playerId, String name) => {
  'id': id,
  'playerId': playerId,
  'name': name,
  'ms': 1800,
  'at': 1000000 + id,
};

PartyState _state({
  String code = 'K7M2',
  int meId = 1,
  List<Map<String, dynamic>> clips = const [],
}) => PartyState.fromJson({
  'code': code,
  'game': 'blind',
  'audioMode': 'host',
  'status': 'playing',
  'phase': 'guessing',
  'version': 3,
  'serverNow': 1000000,
  'phaseAt': 995000,
  'roundMs': 20000,
  'revealMs': 4500,
  'roundIndex': 0,
  'roundCount': 10,
  'maxPlayers': 12,
  'me': {'id': meId, 'name': 'Maxime', 'isHost': true},
  'players': const [],
  'round': null,
  'voice': {'maxMs': 15000, 'minMs': 350, 'clips': clips},
}, _abs);

void main() {
  group('lecture de l\'état', () {
    test('les messages vocaux et leurs bornes sont relus', () {
      final s = _state(clips: [_clip(4, 2, 'Léa')]);
      expect(s.voiceMaxMs, 15000);
      expect(s.voiceMinMs, 350);
      expect(s.voiceClips.single.name, 'Léa');
      expect(s.voiceClips.single.playerId, 2);
      expect(s.voiceClips.single.ms, 1800);
    });

    test('un serveur qui ne connaît pas le talkie-walkie reste jouable', () {
      final s = PartyState.fromJson({
        'code': 'K7M2',
        'game': 'blind',
        'status': 'lobby',
        'phase': 'lobby',
        'players': const [],
      }, _abs);
      expect(s.voiceClips, isEmpty);
      expect(s.voiceMaxMs, 15000);
    });
  });

  group('file d\'écoute', () {
    test('le premier état ne fait que poser le repère', () {
      final inbox = VoiceInbox();
      // Un invité qui arrive en cours de partie n'a pas à subir tout ce qui
      // s'est dit avant lui.
      final fresh = inbox.accept(_state(clips: [_clip(1, 2, 'Léa'), _clip(2, 3, 'Paul')]));
      expect(fresh, isEmpty);
      expect(inbox.lastId, 2);
    });

    test('les messages suivants sont rendus une seule fois', () {
      final inbox = VoiceInbox();
      inbox.accept(_state(clips: [_clip(1, 2, 'Léa')]));

      final fresh = inbox.accept(
        _state(clips: [_clip(1, 2, 'Léa'), _clip(2, 3, 'Paul')]),
      );
      expect(fresh.map((c) => c.id), [2]);

      // Même état relu au sondage suivant : plus rien à jouer.
      expect(
        inbox.accept(_state(clips: [_clip(1, 2, 'Léa'), _clip(2, 3, 'Paul')])),
        isEmpty,
      );
    });

    test('on ne se réécoute jamais soi-même', () {
      final inbox = VoiceInbox();
      inbox.accept(_state());
      final fresh = inbox.accept(
        _state(clips: [_clip(1, 1, 'Maxime'), _clip(2, 2, 'Léa')]),
      );
      expect(fresh.map((c) => c.name), ['Léa']);
      // Le message qu'on a envoyé compte quand même comme vu.
      expect(inbox.lastId, 2);
    });

    test('les messages arrivés ensemble gardent leur ordre', () {
      final inbox = VoiceInbox();
      inbox.accept(_state());
      final fresh = inbox.accept(
        _state(clips: [_clip(7, 2, 'Léa'), _clip(8, 3, 'Paul'), _clip(9, 2, 'Léa')]),
      );
      expect(fresh.map((c) => c.id), [7, 8, 9]);
    });

    test('changer de salon repart d\'une page blanche', () {
      final inbox = VoiceInbox();
      inbox.accept(_state(clips: [_clip(9, 2, 'Léa')]));
      // Nouveau salon : les identifiants recommencent bas, sans quoi les
      // premiers messages seraient pris pour des vieux et jamais joués.
      expect(inbox.accept(_state(code: 'ZZ99', clips: [_clip(1, 2, 'Léa')])), isEmpty);
      final fresh = inbox.accept(
        _state(code: 'ZZ99', clips: [_clip(1, 2, 'Léa'), _clip(2, 2, 'Léa')]),
      );
      expect(fresh.map((c) => c.id), [2]);
    });

    test('un salon vidé de ses messages expirés ne rejoue pas le passé', () {
      final inbox = VoiceInbox();
      inbox.accept(_state(clips: [_clip(1, 2, 'Léa'), _clip(2, 2, 'Léa')]));
      // Le serveur a purgé les vieux messages : la liste rétrécit.
      expect(inbox.accept(_state(clips: [_clip(2, 2, 'Léa')])), isEmpty);
      expect(inbox.lastId, 2);
    });
  });

  test('l\'adresse d\'écoute porte le code et le jeton du salon', () {
    final repo = PartyRepository(ApiClient(serverUrl: 'https://gullify.test'));
    final url = repo.voiceClipUrl('K7M2', 'jeton-abc', 42);
    expect(url, startsWith('https://gullify.test/api/v2/party.php?'));
    expect(url, contains('action=voiceclip'));
    expect(url, contains('code=K7M2'));
    expect(url, contains('token=jeton-abc'));
    expect(url, endsWith('id=42'));
  });

  group('la barre du talkie-walkie', () {
    Future<void> show(WidgetTester tester, PartyVoiceState voice) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: gullifyThemeFor(GullifyAccent.indigo, dark: true),
          home: Scaffold(
            body: TalkBarView(
              voice: voice,
              maxMs: 15000,
              onTalkStart: () {},
              onTalkStop: () {},
              onToggleSpeaker: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('au repos : l\'invitation à parler', (tester) async {
      await show(tester, const PartyVoiceState());
      expect(find.text('Maintiens pour parler'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pendant l\'enregistrement : le décompte', (tester) async {
      await show(
        tester,
        PartyVoiceState(
          recording: true,
          startedAt: DateTime.now().subtract(const Duration(milliseconds: 1500)),
        ),
      );
      expect(find.textContaining('Relâche pour envoyer'), findsOneWidget);
      expect(find.textContaining('1.5 s'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('quand quelqu\'un parle : on sait qui', (tester) async {
      await show(tester, const PartyVoiceState(speakingName: 'Léa'));
      expect(find.text('Léa parle…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('haut-parleur coupé : l\'icône le dit', (tester) async {
      await show(tester, const PartyVoiceState(speakerOn: false));
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('micro refusé : le bouton le montre', (tester) async {
      await show(
        tester,
        const PartyVoiceState(micDenied: true, message: 'Micro refusé'),
      );
      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
      expect(find.text('Micro refusé'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

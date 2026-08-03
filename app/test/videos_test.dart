// Idée #37 : onglet « Vidéos ». Le serveur relaie le flux (les URL YouTube
// sont liées à l'IP qui les résout), d'où l'URL de lecture construite ici.
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/videos_repository.dart';

void main() {
  test('VideoResult lit une réponse de recherche', () {
    final v = VideoResult.fromJson(const {
      'id': 'F79Q-_oOjq0',
      'title': 'Bohemian Rhapsody — Live',
      'channel': 'Queen',
      'duration': 359,
      'thumbnail': 'https://i.ytimg.com/vi/F79Q-_oOjq0/hqdefault.jpg',
      'live': false,
    });
    expect(v.id, 'F79Q-_oOjq0');
    expect(v.duration, const Duration(minutes: 5, seconds: 59));
    expect(v.live, isFalse);
  });

  test('VideoResult tolère les champs manquants', () {
    final v = VideoResult.fromJson(const {'id': 'abcdefghijk'});
    expect(v.title, '');
    expect(v.duration, Duration.zero);
    expect(v.live, isFalse);
  });

  test('ServerVideo distingue prêt, en cours et échec', () {
    ServerVideo of(String status) =>
        ServerVideo.fromJson({'id': 'abcdefghijk', 'status': status});
    expect(of('ready').status, VideoStatus.ready);
    expect(of('ready').isReady, isTrue);
    expect(of('downloading').status, VideoStatus.downloading);
    expect(of('error').status, VideoStatus.error);
    // Un statut inconnu ne doit jamais passer pour « prêt ».
    expect(of('').status, VideoStatus.downloading);
  });

  test('streamUrl vise l\'endpoint de relais du serveur', () {
    final repo = VideosRepository(
      ApiClient(serverUrl: 'gullify.app/', token: 'x'),
    );
    expect(
      repo.streamUrl('F79Q-_oOjq0'),
      'https://gullify.app/api/v2/videos.php?action=stream&id=F79Q-_oOjq0',
    );
  });
}

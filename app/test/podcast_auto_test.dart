import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/podcasts_repository.dart';
import 'package:gullify/audio/audio_handler.dart';

PodcastEpisode episode({
  String guid = 'ep-1',
  int duration = 3600,
  int position = 0,
  bool completed = false,
}) =>
    PodcastEpisode(
      guid: guid,
      title: 'Un épisode',
      audioUrl: 'https://exemple.ca/ep1.mp3',
      description: '',
      duration: duration,
      publishedAt: 0,
      image: '',
      number: 0,
      season: 0,
      position: position,
      completed: completed,
    );

void main() {
  group('les identifiants de balado survivent au voyage', () {
    // Une adresse de flux et un identifiant d'épisode contiennent n'importe
    // quoi, et ces identifiants-ci voyagent dans un protocole qui les traite
    // comme des mots.
    const cas = <String>[
      'https://radio.ca/balados/feed.xml',
      'https://exemple.ca/f?id=12&lang=fr#a',
      'https://exemple.ca/émissions/été_2026',
      'tag:soundcloud,2010:tracks/1234567',
    ];

    test('aller-retour sans perte', () {
      for (final valeur in cas) {
        expect(BrowseIds.decode(BrowseIds.encode(valeur)), valeur,
            reason: valeur);
      }
    });

    test("l'épisode se recoupe au bon endroit", () {
      // Le piège : l'alphabet de base64url contient « - » et « _ ». Un
      // découpage à l'un d'eux tomberait au milieu de l'adresse du flux.
      for (final feed in cas) {
        for (final guid in cas) {
          final id = BrowseIds.podcastEpisode(feed, guid);
          final reste = id.substring('PODEP_'.length);
          final coupure = reste.indexOf('.');

          expect(coupure, greaterThan(0), reason: id);
          expect(BrowseIds.decode(reste.substring(0, coupure)), feed);
          expect(BrowseIds.decode(reste.substring(coupure + 1)), guid);
        }
      }
    });

    test('une série et un épisode ne se confondent pas', () {
      const feed = 'https://radio.ca/f.xml';
      expect(BrowseIds.podcastShow(feed), startsWith('PODCAST_'));
      expect(BrowseIds.podcastEpisode(feed, 'g'), startsWith('PODEP_'));
      // `startsWith('PODCAST_')` ne doit JAMAIS attraper un épisode.
      expect(BrowseIds.podcastEpisode(feed, 'g').startsWith('PODCAST_'), isFalse);
    });
  });

  group('ce qu\'on lit d\'un épisode au volant', () {
    test('un épisode déjà écouté le dit', () {
      expect(
        GullifyAudioHandler.etatEpisode(episode(completed: true), 'La série'),
        'La série · écouté',
      );
    });

    test('un épisode commencé annonce ce qu\'il reste', () {
      expect(
        GullifyAudioHandler.etatEpisode(
            episode(duration: 3600, position: 1200), 'La série'),
        'La série · reprendre, 40 min restantes',
      );
    });

    test('un épisode à peine entamé n\'est pas « repris »', () {
      // Trente secondes, ce n'est pas une écoute : repartir de là ferait
      // manquer le début.
      expect(
        GullifyAudioHandler.etatEpisode(episode(position: 20), 'La série'),
        'La série',
      );
    });

    test('un épisode neuf ne dit que la série', () {
      expect(
        GullifyAudioHandler.etatEpisode(episode(), 'La série'),
        'La série',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/library_repository.dart';

void main() {
  group('la date du serveur suit jusqu\'à l\'en-tête', () {
    // L'adresse de l'en-tête est fabriquée dans l'app (à cause de fetch=1),
    // et n'héritait donc d'aucune date : une photo changée sur le serveur
    // restait l'ancienne sur le téléphone, tirée de son cache.
    test('la date est reprise telle quelle', () {
      expect(
        LibraryRepository.dateDeAdresse('https://m.gullify.app/serve_image.php?artist_id=7&v=1759330000'),
        '&v=1759330000',
      );
      expect(LibraryRepository.dateDeAdresse('serve_image.php?artist_id=7'), '');
      expect(LibraryRepository.dateDeAdresse(null), '');
    });

    test('elle se retrouve dans l\'adresse de l\'en-tête', () {
      final url = LibraryRepository.cheminImageArtiste(7, '&v=1759330000');
      expect(url, contains('artist_id=7'));
      expect(url, contains('fetch=1'));
      expect(url, endsWith('&v=1759330000'));
    });
  });
}

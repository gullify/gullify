// L'image d'en-tête d'un artiste (idée #67) passe par serve_image.php avec
// `fetch=1` : le serveur a le droit d'aller la chercher sur le web pour CET
// artiste. Le contrat est une chaîne de requête — un test le fige, faute de
// quoi une faute de frappe se voit seulement en regardant un logo Gullify.
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';

void main() {
  final repo = LibraryRepository(ApiClient(serverUrl: 'https://gullify.app'));

  test("l'en-tête d'artiste autorise la récupération web", () {
    final url = Uri.parse(repo.artistImageUrl(42));

    expect(url.path, '/serve_image.php');
    expect(url.queryParameters['artist_id'], '42');
    expect(url.queryParameters['fetch'], '1');
    // Rien nulle part : l'app préfère sa propre icône au logo Gullify.
    expect(url.queryParameters['fallback'], '404');
  });
}

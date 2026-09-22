// Le flux audio est signé.
//
// `stream.php` exige désormais un jeton : il n'était protégé par rien, et
// qui connaissait le chemin d'un fichier pouvait l'écouter depuis n'importe
// où. Une balise `<audio>` ne peut pas poser d'en-tête `Authorization` — le
// jeton voyage donc dans l'adresse.
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/library_repository.dart';
import 'package:gullify/models/song.dart';

const _chanson = Song(
  id: 1,
  title: 'Ruby Soho',
  filePath: 'Rancid/And Out Come the Wolves/03 Ruby Soho.mp3',
  duration: 158,
);

void main() {
  ApiClient client({String? jeton}) =>
      ApiClient(serverUrl: 'https://gullify.app', token: jeton);

  test('le flux porte le jeton de session', () {
    final url = LibraryRepository(client(jeton: 'abc123')).streamUrl(_chanson);
    expect(url, startsWith('https://gullify.app/stream.php?path='));
    expect(url, contains('&token=abc123'));
    expect(
      url,
      contains('path=Rancid%2FAnd+Out+Come+the+Wolves%2F03+Ruby+Soho.mp3'),
      reason: 'le chemin reste échappé',
    );
  });

  test('la version karaoké aussi', () {
    final url = LibraryRepository(
      client(jeton: 'abc123'),
    ).streamUrlForPath('a.mp3', karaoke: true);
    expect(url, contains('&karaoke=1'));
    expect(url, contains('&token=abc123'));
  });

  test('un jeton qui contient des caractères spéciaux est échappé', () {
    final url = client(jeton: 'a+b/c=').mediaUrl('stream.php?path=x');
    expect(url, endsWith('&token=a%2Bb%2Fc%3D'));
  });

  test('sans jeton, l\'adresse part telle quelle — le serveur répondra 401', () {
    final url = LibraryRepository(client()).streamUrl(_chanson);
    expect(url, isNot(contains('token=')));
  });

  test('une adresse sans paramètre reçoit le jeton en premier', () {
    expect(client(jeton: 'z').mediaUrl('serve_avatar.php'),
        endsWith('serve_avatar.php?token=z'));
  });
}

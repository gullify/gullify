// Idée #68 : partager une chanson par un lien d'écoute qui s'efface au bout
// de 24 h. Idée #89 : le même lien, mais pour un album ou un artiste entier.
// Le serveur fait tout le travail (jeton, échéance, liste des titres, flux) ;
// ce qui se teste ici, c'est que l'app demande le bon partage, lise sa
// réponse, et que la feuille montre le lien, sache le couper, et ne mente pas
// quand la création échoue.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gullify/api/api_client.dart';
import 'package:gullify/api/share_repository.dart';
import 'package:gullify/models/album.dart';
import 'package:gullify/models/artist.dart';
import 'package:gullify/models/song.dart';
import 'package:gullify/state/shares.dart';
import 'package:gullify/widgets/share_sheet.dart';

class _FakeShareRepo extends Fake implements ShareRepository {
  _FakeShareRepo({this.link, this.error});

  final SongShareLink? link;
  final Object? error;
  final List<(ShareKind, int)> created = [];
  final List<String> revoked = [];

  @override
  Future<SongShareLink> create(ShareKind kind, int id) async {
    created.add((kind, id));
    if (error != null) throw error!;
    return link!;
  }

  @override
  Future<void> revoke(String token) async => revoked.add(token);
}

const _song = Song(
  id: 90262,
  title: 'Allo la lune',
  filePath: 'fredou/Fredz/Demain il fera beau/01 - Allo la lune.mp3',
  albumId: 14640,
  albumName: 'Demain il fera beau',
  artistName: 'Fredz',
);

const _album = Album(
  id: 14640,
  name: 'Demain il fera beau',
  artistId: 812,
  artistName: 'Fredz',
);

const _artist = Artist(id: 812, name: 'Fredz');

SongShareLink _link({
  Duration remaining = const Duration(hours: 24),
  ShareKind kind = ShareKind.song,
  int trackCount = 1,
}) => SongShareLink(
  token: '23dc5f7f88ea446691',
  url: 'https://gullify.app/s/23dc5f7f88ea446691',
  title: 'Allo la lune',
  artist: 'Fredz',
  kind: kind,
  remaining: remaining,
  trackCount: trackCount,
);

Future<void> _open(
  WidgetTester tester,
  _FakeShareRepo repo, {
  ShareTarget? target,
}) async {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [shareRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showShareSheet(
                context,
                target ?? ShareTarget.song(_song),
              ),
              child: const Text('partager'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('partager'));
  await tester.pumpAndSettle();
}

void main() {
  test('SongShareLink lit la réponse du serveur', () {
    final link = SongShareLink.fromJson(const {
      'token': '23dc5f7f88ea446691',
      'url': 'https://gullify.app/s/23dc5f7f88ea446691',
      'kind': 'album',
      'title': 'Demain il fera beau',
      'artist': 'Fredz',
      'artworkUrl': 'https://gullify.app/serve_image.php?album_id=14640',
      'remainingMs': 86400000,
      'trackCount': 12,
      'plays': 2,
    });
    expect(link.token, '23dc5f7f88ea446691');
    expect(link.kind, ShareKind.album);
    expect(link.remaining, const Duration(hours: 24));
    expect(link.trackCount, 12);
    expect(link.plays, 2);
    expect(link.artworkUrl, isNotNull);
  });

  test('SongShareLink tolère une réponse incomplète', () {
    final link = SongShareLink.fromJson(const {'token': 'abc'});
    expect(link.url, '');
    expect(link.remaining, Duration.zero);
    // Un lien d'avant l'idée #89 ne dit pas ce qu'il porte : c'est une
    // chanson, et une seule.
    expect(link.kind, ShareKind.song);
    expect(link.trackCount, 1);
    // Pas de pochette : il ne faut pas d'URL vide, qui ferait un chargement
    // d'image voué à l'échec.
    expect(link.artworkUrl, isNull);
  });

  test('la durée restante s\'annonce en heures et en minutes', () {
    String label(Duration d) => _link(remaining: d).remainingLabel;
    expect(label(const Duration(hours: 24)), '24 h');
    expect(label(const Duration(hours: 3, minutes: 20)), '3 h 20');
    expect(label(const Duration(minutes: 45)), '45 min');
    expect(label(const Duration(seconds: 30)), 'moins d\'une minute');
  });

  test('le SMS proposé se tourne selon ce qu\'on partage', () {
    const url = 'https://gullify.app/s/23dc5f7f88ea446691';
    expect(
      ShareTarget.song(_song).smsBody(url),
      'Écoute « Allo la lune » de Fredz sur Gullify : $url',
    );
    expect(
      ShareTarget.album(_album).smsBody(url),
      'Écoute l\'album « Demain il fera beau » de Fredz sur Gullify : $url',
    );
    expect(ShareTarget.artist(_artist).smsBody(url),
        'Écoute Fredz sur Gullify : $url');
  });

  testWidgets('la feuille demande le lien et le montre', (tester) async {
    final repo = _FakeShareRepo(link: _link());
    await _open(tester, repo);

    expect(repo.created, [(ShareKind.song, 90262)]);
    expect(find.text('https://gullify.app/s/23dc5f7f88ea446691'), findsOneWidget);
    expect(find.textContaining('24 h'), findsOneWidget);
    expect(find.text('Envoyer par SMS'), findsOneWidget);
    // La chanson partagée reste identifiable dans la feuille.
    expect(find.text('Allo la lune'), findsOneWidget);
    expect(find.text('Fredz'), findsOneWidget);
  });

  testWidgets('un album se partage entier, et le dit', (tester) async {
    final repo = _FakeShareRepo(
      link: _link(kind: ShareKind.album, trackCount: 12),
    );
    await _open(tester, repo, target: ShareTarget.album(_album));

    // C'est bien l'album qui part au serveur, pas l'une de ses chansons.
    expect(repo.created, [(ShareKind.album, 14640)]);
    expect(find.text('Demain il fera beau'), findsOneWidget);
    // Le nombre de titres est annoncé : on sait ce qu'on envoie.
    expect(find.textContaining('12 titres'), findsOneWidget);
  });

  testWidgets('un artiste se partage aussi', (tester) async {
    final repo = _FakeShareRepo(
      link: _link(kind: ShareKind.artist, trackCount: 48),
    );
    await _open(tester, repo, target: ShareTarget.artist(_artist));

    expect(repo.created, [(ShareKind.artist, 812)]);
    expect(find.textContaining('48 titres'), findsOneWidget);
    expect(find.text('Envoyer par SMS'), findsOneWidget);
  });

  testWidgets('« Désactiver le lien » le coupe et referme la feuille',
      (tester) async {
    final repo = _FakeShareRepo(link: _link());
    await _open(tester, repo);

    await tester.tap(find.text('Désactiver le lien'));
    await tester.pumpAndSettle();

    expect(repo.revoked, ['23dc5f7f88ea446691']);
    expect(find.text('Envoyer par SMS'), findsNothing);
    expect(find.text('Lien désactivé'), findsOneWidget);
  });

  testWidgets('un échec du serveur se dit, et se réessaie', (tester) async {
    final repo = _FakeShareRepo(
      error: ApiException('too_many_shares', 'Trop de liens en cours'),
    );
    await _open(tester, repo);

    expect(find.text('Trop de liens en cours'), findsOneWidget);
    // Aucun lien inventé : rien à envoyer tant que le serveur n'en donne pas.
    expect(find.text('Envoyer par SMS'), findsNothing);

    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(repo.created, [
      (ShareKind.song, 90262),
      (ShareKind.song, 90262),
    ]);
  });
}

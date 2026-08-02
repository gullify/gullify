import 'song.dart';

/// Un titre daté : la carte de base des jeux « Chrono » et « Duel d'années ».
/// L'année vient de l'album (seule donnée de millésime de la bibliothèque),
/// le titre reste jouable pour l'extrait audio.
class GameTrack {
  const GameTrack({required this.song, required this.year});

  final Song song;
  final int year;

  int? get albumId => song.albumId;
}

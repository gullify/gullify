import 'package:freezed_annotation/freezed_annotation.dart';

part 'artist.freezed.dart';
part 'artist.g.dart';

@freezed
abstract class Artist with _$Artist {
  const factory Artist({
    required int id,
    required String name,
    String? imageUrl,
    String? genre,

    /// Tous ses genres, le principal en tête (serveur 1.20.0) ; [genre] reste
    /// le principal, pour les serveurs d'avant.
    @Default(<String>[]) List<String> genres,

    /// D'où vient l'artiste (Québec, France…), à part des genres.
    String? origine,
    @Default(0) int albumCount,
    @Default(0) int songCount,
  }) = _Artist;

  factory Artist.fromJson(Map<String, dynamic> json) => _$ArtistFromJson(json);
}

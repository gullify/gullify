import 'package:freezed_annotation/freezed_annotation.dart';

part 'album.freezed.dart';
part 'album.g.dart';

@freezed
abstract class Album with _$Album {
  const factory Album({
    required int id,
    required String name,
    int? artistId,
    String? artistName,
    int? year,
    String? artworkUrl,
    @Default(0) int songCount,
    int? totalDuration,
  }) = _Album;

  factory Album.fromJson(Map<String, dynamic> json) => _$AlbumFromJson(json);
}

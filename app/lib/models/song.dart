import 'package:freezed_annotation/freezed_annotation.dart';

part 'song.freezed.dart';
part 'song.g.dart';

@freezed
abstract class Song with _$Song {
  const factory Song({
    required int id,
    required String title,
    required String filePath,
    int? trackNumber,
    @Default(0) int duration,
    int? albumId,
    String? albumName,
    int? artistId,
    String? artistName,
    String? artworkUrl,
  }) = _Song;

  factory Song.fromJson(Map<String, dynamic> json) => _$SongFromJson(json);
}

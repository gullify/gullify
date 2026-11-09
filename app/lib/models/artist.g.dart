// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'artist.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Artist _$ArtistFromJson(Map<String, dynamic> json) => _Artist(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  imageUrl: json['imageUrl'] as String?,
  genre: json['genre'] as String?,
  genres:
      (json['genres'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  origine: json['origine'] as String?,
  albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
  songCount: (json['songCount'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$ArtistToJson(_Artist instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'imageUrl': instance.imageUrl,
  'genre': instance.genre,
  'genres': instance.genres,
  'origine': instance.origine,
  'albumCount': instance.albumCount,
  'songCount': instance.songCount,
};

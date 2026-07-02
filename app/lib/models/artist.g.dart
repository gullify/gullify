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
  albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
  songCount: (json['songCount'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$ArtistToJson(_Artist instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'imageUrl': instance.imageUrl,
  'genre': instance.genre,
  'albumCount': instance.albumCount,
  'songCount': instance.songCount,
};

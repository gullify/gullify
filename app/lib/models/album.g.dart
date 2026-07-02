// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Album _$AlbumFromJson(Map<String, dynamic> json) => _Album(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  artistId: (json['artistId'] as num?)?.toInt(),
  artistName: json['artistName'] as String?,
  year: (json['year'] as num?)?.toInt(),
  artworkUrl: json['artworkUrl'] as String?,
  songCount: (json['songCount'] as num?)?.toInt() ?? 0,
  totalDuration: (json['totalDuration'] as num?)?.toInt(),
);

Map<String, dynamic> _$AlbumToJson(_Album instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'artistId': instance.artistId,
  'artistName': instance.artistName,
  'year': instance.year,
  'artworkUrl': instance.artworkUrl,
  'songCount': instance.songCount,
  'totalDuration': instance.totalDuration,
};

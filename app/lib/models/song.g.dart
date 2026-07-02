// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Song _$SongFromJson(Map<String, dynamic> json) => _Song(
  id: (json['id'] as num).toInt(),
  title: json['title'] as String,
  filePath: json['filePath'] as String,
  trackNumber: (json['trackNumber'] as num?)?.toInt(),
  duration: (json['duration'] as num?)?.toInt() ?? 0,
  albumId: (json['albumId'] as num?)?.toInt(),
  albumName: json['albumName'] as String?,
  artistId: (json['artistId'] as num?)?.toInt(),
  artistName: json['artistName'] as String?,
  artworkUrl: json['artworkUrl'] as String?,
);

Map<String, dynamic> _$SongToJson(_Song instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'filePath': instance.filePath,
  'trackNumber': instance.trackNumber,
  'duration': instance.duration,
  'albumId': instance.albumId,
  'albumName': instance.albumName,
  'artistId': instance.artistId,
  'artistName': instance.artistName,
  'artworkUrl': instance.artworkUrl,
};

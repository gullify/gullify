#!/usr/bin/env python3
"""
Récupère les albums d'un artiste depuis YouTube Music en utilisant ytmusicapi
"""
import sys
import json
from ytmusicapi import YTMusic

def get_artist_albums(channel_id):
    """Récupère les albums d'un artiste via son channel ID"""
    try:
        ytmusic = YTMusic()

        # Récupérer les informations de l'artiste et ses albums
        try:
            artist_data = ytmusic.get_artist(channel_id)
        except Exception as e:
            # Si get_artist échoue, essayer une recherche alternative
            # Cela peut arriver avec certains artistes majeurs
            return {'artist': None, 'albums': []}

        # Extraire les informations de l'artiste
        artist_info = None
        if artist_data:
            artist_thumbnail = ''
            if 'thumbnails' in artist_data and artist_data['thumbnails']:
                # Prendre la meilleure qualité (dernière image)
                artist_thumbnail = artist_data['thumbnails'][-1].get('url', '')

            artist_info = {
                'name': artist_data.get('name', ''),
                'thumbnail': artist_thumbnail,
                'channelId': artist_data.get('channelId', channel_id)
            }

        albums = []

        # Parcourir les albums si disponibles
        if 'albums' in artist_data and artist_data['albums']:
            if 'results' in artist_data['albums']:
                album_list = artist_data['albums']['results']
            elif 'browseId' in artist_data['albums']:
                # Si on a seulement un browseId, faire une requête pour les albums
                try:
                    albums_browse = ytmusic.get_artist_albums(channel_id, artist_data['albums']['browseId'])
                    album_list = albums_browse if isinstance(albums_browse, list) else []
                except:
                    album_list = []
            else:
                album_list = artist_data['albums']

            for album in album_list:
                # Extraire les informations de l'album
                album_id = album.get('browseId', '')

                # Les albums YouTube Music ont des browseIds, on doit extraire le playlistId
                playlist_id = None
                album_details = None
                year = album.get('year', None)

                if 'playlistId' in album:
                    playlist_id = album['playlistId']

                # Si on a un browseId MPREb_, récupérer les détails complets de l'album
                if album_id.startswith('MPREb_'):
                    try:
                        album_details = ytmusic.get_album(album_id)
                        if 'audioPlaylistId' in album_details:
                            playlist_id = album_details['audioPlaylistId']
                        # Récupérer l'année depuis les détails de l'album
                        if 'year' in album_details and album_details['year']:
                            year = album_details['year']
                    except:
                        pass

                if not playlist_id:
                    continue

                title = album.get('title', '')

                # Thumbnail
                thumbnail = ''
                if 'thumbnails' in album and album['thumbnails']:
                    thumbnail = album['thumbnails'][-1].get('url', '')

                albums.append({
                    'id': playlist_id,
                    'title': title,
                    'year': year,
                    'url': f'https://music.youtube.com/playlist?list={playlist_id}',
                    'thumbnail': thumbnail,
                    'trackCount': None,
                    'source': 'youtube_music',
                    'uploader': 'YouTube Music'
                })

        return {'artist': artist_info, 'albums': albums}

    except Exception as e:
        print(json.dumps({'error': True, 'message': str(e)}), file=sys.stderr)
        return {'artist': None, 'albums': []}

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(json.dumps({'error': True, 'message': 'Channel ID required'}))
        sys.exit(1)

    channel_id = sys.argv[1]
    result = get_artist_albums(channel_id)

    print(json.dumps(result, ensure_ascii=False, indent=2))

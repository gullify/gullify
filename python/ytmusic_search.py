#!/usr/bin/env python3
"""
YouTube Music Search Helper
Uses ytmusicapi to search for albums, tracks, and artists
"""

import sys
import json

try:
    from ytmusicapi import YTMusic
except ImportError:
    print(json.dumps({"error": "ytmusicapi not installed", "results": []}))
    sys.exit(0)

def search_albums(query):
    """Search for albums on YouTube Music"""
    try:
        ytmusic = YTMusic()
        results = ytmusic.search(query, filter="albums", limit=10)

        albums = []
        for item in results:
            albums.append({
                "title": item.get("title", ""),
                "artist": ", ".join([a.get("name", "") for a in item.get("artists", [])]),
                "year": item.get("year", ""),
                "browseId": item.get("browseId", ""),
                "thumbnail": item.get("thumbnails", [{}])[-1].get("url", "") if item.get("thumbnails") else "",
                "type": "album"
            })

        return albums
    except Exception as e:
        return []

def search_songs(query):
    """Search for songs on YouTube Music"""
    try:
        ytmusic = YTMusic()
        results = ytmusic.search(query, filter="songs", limit=10)

        songs = []
        for item in results:
            songs.append({
                "title": item.get("title", ""),
                "artist": ", ".join([a.get("name", "") for a in item.get("artists", [])]),
                "album": item.get("album", {}).get("name", "") if item.get("album") else "",
                "duration": item.get("duration", ""),
                "videoId": item.get("videoId", ""),
                "thumbnail": item.get("thumbnails", [{}])[-1].get("url", "") if item.get("thumbnails") else "",
                "type": "song"
            })

        return songs
    except Exception as e:
        return []

def search_artists(query):
    """Search for artists on YouTube Music"""
    try:
        ytmusic = YTMusic()
        results = ytmusic.search(query, filter="artists", limit=10)

        artists = []
        for item in results:
            artists.append({
                "name": item.get("artist", ""),
                "browseId": item.get("browseId", ""),
                "thumbnail": item.get("thumbnails", [{}])[-1].get("url", "") if item.get("thumbnails") else "",
                "type": "artist"
            })

        return artists
    except Exception as e:
        return []

def get_album_details(browse_id):
    """Get detailed album information including track listing"""
    try:
        ytmusic = YTMusic()
        album = ytmusic.get_album(browse_id)

        tracks = []
        for i, track in enumerate(album.get("tracks", []), 1):
            tracks.append({
                "track_number": i,
                "title": track.get("title", ""),
                "artist": ", ".join([a.get("name", "") for a in track.get("artists", [])]),
                "duration": track.get("duration", ""),
                "videoId": track.get("videoId", ""),
            })

        return {
            "title": album.get("title", ""),
            "artist": ", ".join([a.get("name", "") for a in album.get("artists", [])]),
            "year": album.get("year", ""),
            "thumbnail": album.get("thumbnails", [{}])[-1].get("url", "") if album.get("thumbnails") else "",
            "track_count": album.get("trackCount", 0),
            "tracks": tracks,
            "type": album.get("type", "Album"),
            "audioPlaylistId": album.get("audioPlaylistId", ""),
        }
    except Exception as e:
        return None

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: ytmusic_search.py <type> <query>", "results": []}))
        sys.exit(1)

    search_type = sys.argv[1]
    query = sys.argv[2]

    results = []

    if search_type == "album":
        results = search_albums(query)
    elif search_type == "song" or search_type == "track":
        results = search_songs(query)
    elif search_type == "artist":
        results = search_artists(query)
    elif search_type == "album_details":
        # query is actually browseId in this case
        details = get_album_details(query)
        print(json.dumps({"album": details}))
        sys.exit(0)
    else:
        # Default: search all
        results = search_songs(query) + search_albums(query)

    print(json.dumps({"results": results}))

if __name__ == "__main__":
    main()

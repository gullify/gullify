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

# Pays annoncé à YouTube Music : sans lui il devine d'après l'IP du serveur, et
# les disponibilités comme l'ordre des résultats suivent alors le mauvais
# marché. On dit donc « Canada » partout.
#
# La langue, elle, reste l'anglais : ytmusicapi 1.12 ne sait pas relire une
# réponse en français (la recherche de chansons revient vide), et les libellés
# qu'on teste ici — « Album » d'une tuile de nouveauté — sont ceux de l'anglais.
LOCATION = "CA"

def _client():
    """Client YouTube Music localisé, avec repli sur les réglages par défaut."""
    try:
        return YTMusic(location=LOCATION)
    except Exception:
        return YTMusic()

def search_albums(query, limit=10):
    """Search for albums on YouTube Music"""
    try:
        ytmusic = _client()
        results = ytmusic.search(query, filter="albums", limit=limit)

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

def search_songs(query, limit=10):
    """Search for songs on YouTube Music"""
    try:
        ytmusic = _client()
        results = ytmusic.search(query, filter="songs", limit=limit)

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

def search_artists(query, limit=10):
    """Search for artists on YouTube Music"""
    try:
        ytmusic = _client()
        results = ytmusic.search(query, filter="artists", limit=limit)

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

def artist_albums(browse_id, limit=50):
    """Discographie réelle d'un artiste (albums + singles) via son browseId.

    La recherche d'albums par nom mélange d'autres artistes ; passer par
    get_artist(browseId) donne la vraie discographie de l'artiste choisi.
    """
    try:
        ytmusic = _client()
        artist = ytmusic.get_artist(browse_id)
        name = artist.get("name", "")
        out = []
        seen = set()

        def add(item, kind):
            bid = item.get("browseId", "")
            if not bid or bid in seen:
                return
            seen.add(bid)
            out.append({
                "title": item.get("title", ""),
                "artist": name,
                "year": item.get("year", ""),
                "browseId": bid,
                "thumbnail": item.get("thumbnails", [{}])[-1].get("url", "")
                    if item.get("thumbnails") else "",
                "type": kind,
            })

        for kind in ("albums", "singles"):
            section = artist.get(kind) or {}
            results = section.get("results", []) or []
            # Liste complète si YouTube en propose une (params + channelId).
            if section.get("params") and section.get("browseId"):
                try:
                    full = ytmusic.get_artist_albums(
                        section["browseId"], section["params"])
                    if full:
                        results = full
                except Exception:
                    pass
            for item in results:
                add(item, kind)

        return out[:limit]
    except Exception:
        return []

def related_artists(query):
    """Artistes similaires : cherche l'artiste, puis lit ses artistes liés."""
    try:
        ytmusic = _client()
        found = ytmusic.search(query, filter="artists", limit=1)
        if not found:
            return []
        browse_id = found[0].get("browseId", "")
        if not browse_id:
            return []
        artist = ytmusic.get_artist(browse_id)
        related = (artist.get("related") or {}).get("results", []) or []
        out = []
        for item in related:
            out.append({
                "name": item.get("title", ""),
                "browseId": item.get("browseId", ""),
                "thumbnail": item.get("thumbnails", [{}])[-1].get("url", "")
                    if item.get("thumbnails") else "",
                "type": "artist",
            })
        return [a for a in out if a["name"]]
    except Exception:
        return []

def _two_row_items(node):
    """Parcourt une réponse « browse » et rend ses tuiles (musicTwoRowItemRenderer)."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "musicTwoRowItemRenderer":
                yield value
            else:
                yield from _two_row_items(value)
    elif isinstance(node, list):
        for value in node:
            yield from _two_row_items(value)

def _new_releases_page(ytmusic):
    """Page « Nouveautés » complète de YouTube Music (~170 sorties).

    Chaque tuile porte un sous-titre « Album • Artiste » (ou « Single »/« EP ») :
    on ne garde que les albums. Endpoint non exposé par ytmusicapi, d'où l'appel
    direct — le repli sur get_explore() couvre un changement d'API.
    """
    response = ytmusic._send_request(
        "browse", {"browseId": "FEmusic_new_releases_albums"})
    out = []
    seen = set()
    for item in _two_row_items(response):
        subtitle = [r.get("text", "") for r in
                    (item.get("subtitle") or {}).get("runs", [])]
        if not subtitle or subtitle[0] != "Album":
            continue  # single, EP, playlist…
        endpoint = (item.get("navigationEndpoint") or {}).get("browseEndpoint") or {}
        browse_id = endpoint.get("browseId", "")
        if not browse_id or browse_id in seen:
            continue
        title_runs = (item.get("title") or {}).get("runs", [])
        title = title_runs[0].get("text", "") if title_runs else ""
        if not title:
            continue
        seen.add(browse_id)
        thumbs = ((item.get("thumbnailRenderer") or {})
                  .get("musicThumbnailRenderer", {})
                  .get("thumbnail", {})
                  .get("thumbnails", []))
        out.append({
            "title": title,
            # runs[1] est le séparateur « • » ; le reste nomme le ou les artistes.
            "artist": "".join(subtitle[2:]).strip(),
            "year": "",
            "browseId": browse_id,
            "thumbnail": thumbs[-1].get("url", "") if thumbs else "",
            "type": "album",
        })
    return out

def new_releases(limit=30):
    """Nouvelles sorties YouTube Music, albums seulement (pas de singles/EP).

    Cette page-là ignore le pays : CA, US, FR ou JP renvoient exactement les
    mêmes albums, dans un ordre à peine différent. C'est donc un fourre-tout
    mondial, que le serveur (download.php) reclasse ensuite par pertinence.
    """
    try:
        ytmusic = _client()
    except Exception:
        return []

    try:
        albums = _new_releases_page(ytmusic)
    except Exception:
        albums = []

    if not albums:
        # Repli : les nouveautés de la page Explorer (moins nombreuses).
        try:
            explore = ytmusic.get_explore()
        except Exception:
            return []
        for item in explore.get("new_releases", []) or []:
            if item.get("type") != "Album" or not item.get("browseId"):
                continue
            albums.append({
                "title": item.get("title", ""),
                "artist": ", ".join(
                    [a.get("name", "") for a in item.get("artists", []) or []]),
                "year": "",
                "browseId": item.get("browseId", ""),
                "thumbnail": item.get("thumbnails", [{}])[-1].get("url", "")
                    if item.get("thumbnails") else "",
                "type": "album",
            })

    return albums[:limit]

def get_album_details(browse_id):
    """Get detailed album information including track listing"""
    try:
        ytmusic = _client()
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
    # « new_releases » n'a pas de requête : son 2e argument est la limite.
    if len(sys.argv) >= 2 and sys.argv[1] == "new_releases":
        limit = 30
        if len(sys.argv) >= 3:
            try:
                limit = max(1, min(100, int(sys.argv[2])))
            except ValueError:
                pass
        print(json.dumps({"results": new_releases(limit)}))
        sys.exit(0)

    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: ytmusic_search.py <type> <query>", "results": []}))
        sys.exit(1)

    search_type = sys.argv[1]
    query = sys.argv[2]

    # Optionnel : 3e argument = nombre de résultats souhaités (« charger plus »).
    limit = 10
    if len(sys.argv) >= 4:
        try:
            limit = max(1, min(50, int(sys.argv[3])))
        except ValueError:
            limit = 10

    results = []

    if search_type == "album":
        results = search_albums(query, limit)
    elif search_type == "song" or search_type == "track":
        results = search_songs(query, limit)
    elif search_type == "artist":
        results = search_artists(query, limit)
    elif search_type == "artist_albums":
        # query est ici le browseId de l'artiste choisi.
        results = artist_albums(query, limit)
    elif search_type == "related":
        results = related_artists(query)
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
